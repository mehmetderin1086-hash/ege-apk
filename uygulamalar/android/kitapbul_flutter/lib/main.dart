import 'cover_fetch.dart';
import 'data_quality.dart';
import 'data_quality_page.dart';
import 'student_profile_page.dart';
import 'student_cards_page.dart';
import 'student_card.dart';
import 'reading_champions_page.dart';
import 'class_loan_page.dart';
import 'textbook_page.dart';
import 'catalog_store.dart';
import 'student_store.dart';
import 'member_store.dart';
import 'student_csv.dart';
import 'student_promotion.dart';
import 'reservation_model.dart';
import 'reservation_notifications.dart';
import 'loan_reminders.dart';
import 'iphone_archive.dart';
import 'zip_backup.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'book_images.dart';
import 'package:flutter/services.dart';
import 'loan_model.dart';
import 'loan_settings.dart';
import 'ocr_review.dart';
import 'ocr_extract.dart';
import 'isbn.dart';
import 'isbn_scanner.dart';
import 'inventory_page.dart';
import 'inventory_session.dart';
import 'book_lookup.dart';
import 'book_visuals.dart';
import 'book_editor_sheet.dart';
import 'catalog_views.dart';
import 'catalog_xlsx.dart';
import 'library_discovery_page.dart';
import 'students_directory_page.dart';
import 'kitapyurdu_search_dialog.dart';
import 'quick_register_page.dart';
import 'catalog_search.dart';
import 'class_summary.dart';
import 'catalog_merge.dart';
import 'catalog_csv.dart';
import 'app_theme_settings.dart';
import 'iphone_seed_loader.dart';
import 'school_duty_roster.dart';
import 'library_atmosphere_studio.dart';
import 'library_labels_page.dart';
import 'circulation_desk_page.dart';
import 'school_automation_hub.dart';
import 'ai_proxy_service.dart';
import 'bulk_isbn_importer_page.dart';
import 'ai_book_vision_page.dart';
import 'shelf_photo_scanner_page.dart';
import 'voice_assistant_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

ThemeData _tema(Brightness parlaklik, Color anaRenk) {
  final scheme = ColorScheme.fromSeed(
    seedColor: anaRenk,
    brightness: parlaklik,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface.withValues(alpha: 0.72),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow.withValues(alpha: 0.82),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow.withValues(alpha: 0.86),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

void main() => runApp(
  ValueListenableBuilder<AppThemeSettings>(
    valueListenable: appThemeNotifier,
    builder: (_, cfg, _) => MaterialApp(
      title: 'Kitap Bul',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _tema(Brightness.light, cfg.preset.seed),
      darkTheme: _tema(Brightness.dark, cfg.preset.seed),
      themeMode: cfg.themeMode,
      home: const Library(),
    ),
  ),
);

class Library extends StatefulWidget {
  const Library({super.key});
  @override
  State<Library> createState() => _LibraryState();
}

class _LibraryState extends State<Library> {
  List<Map<String, dynamic>> books = [];
  List<Student> students = [];
  List<Member> members = [];
  String query = '';
  final searchController = TextEditingController();
  final ValueNotifier<double> _scrollParallax = ValueNotifier<double>(0);
  bool loading = true;
  bool saving = false;
  int tab = 0;
  CatalogViewMode viewMode = CatalogViewMode.showcaseGrid;
  bool heroCollapsed = false;
  bool filtersExpanded = false;
  bool overdueOnly = false;
  LoanSettings loanSettings = const LoanSettings();
  bool showWithdrawn = false;
  String? selectedCategory;
  String? selectedShelf;
  String statusFilter = 'all';
  final Set<String> selectedBookIds = <String>{};
  String sortMode = 'default';
  String loadingMessage = 'Kütüphane hazırlanıyor...';
  SchoolDutyRoster dutyRoster = SchoolDutyRoster(
    days: defaultCumhuriyetDutySchedule(),
  );
  DataQualityField? qualityFilter;
  String? error;
  bool backupAvailable = false;
  Future<void> _notificationQueue = Future.value();

  bool _selectionActive = false;

  bool get selectionMode => _selectionActive || selectedBookIds.isNotEmpty;

  void toggleBookSelection(String id) {
    if (id.isEmpty) return;
    setState(() {
      _selectionActive = true;
      if (selectedBookIds.contains(id)) {
        selectedBookIds.remove(id);
        if (selectedBookIds.isEmpty) _selectionActive = false;
      } else {
        selectedBookIds.add(id);
      }
    });
  }

  void clearBookSelection() {
    if (!_selectionActive && selectedBookIds.isEmpty) return;
    setState(() {
      _selectionActive = false;
      selectedBookIds.clear();
    });
  }

  Future<void> toggleFavorite(Map<String, dynamic> book) async {
    if (saving) return;
    final nextVal = !(book['isFavorite'] == true);
    final nextBooks = books
        .map(
          (b) => b['id'] == book['id'] ? {...b, 'isFavorite': nextVal} : b,
        )
        .toList();
    await save(nextBooks);
  }

  Future<void> rateBook(Map<String, dynamic> book, int nextRating) async {
    if (saving) return;
    final clamped = nextRating.clamp(0, 5);
    final nextBooks = books.map((b) {
      if (b['id'] != book['id']) return b;
      final copy = Map<String, dynamic>.from(b);
      if (clamped == 0) {
        copy.remove('rating');
      } else {
        copy['rating'] = clamped;
      }
      return copy;
    }).toList();
    await save(nextBooks);
  }

  Future<void> quickExtendLoan(
    Map<String, dynamic> book,
    String loanId, {
    int days = 7,
  }) async {
    if (saving) return;
    final loans = activeLoans(book);
    final record = loans.where((l) => l['id'] == loanId).firstOrNull;
    if (record == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final previous = DateTime.tryParse(record['due']?.toString() ?? '');
    final base = previous != null && previous.isAfter(today)
        ? DateTime(previous.year, previous.month, previous.day)
        : today;
    final target = base.add(Duration(days: days));
    await save(
      books
          .map((b) => b['id'] == book['id'] ? extendLoan(b, loanId, target) : b)
          .toList(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${book['title']}" süresi +$days gün uzatıldı (${target.day}.${target.month}.${target.year}).',
          ),
        ),
      );
    }
  }

  Future<void> _batchUpdateBookField({
    required String title,
    required String fieldLabel,
    required String fieldKey,
    required List<String> suggestions,
  }) async {
    if (saving || selectedBookIds.isEmpty) return;
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$title (${selectedBookIds.length} kitap)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: fieldLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in suggestions)
                      ActionChip(
                        label: Text(s),
                        onPressed: () => ctrl.text = s,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Toplu Uygula'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    final targetIds = {...selectedBookIds};
    final nextBooks = books
        .map((b) => targetIds.contains(b['id']) ? {...b, fieldKey: value} : b)
        .toList();
    await save(nextBooks);
    if (mounted) {
      setState(() => selectedBookIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${targetIds.length} kitabın bilgisi güncellendi.'),
        ),
      );
    }
  }

  Future<void> _batchMoveToTrash() async {
    if (saving || selectedBookIds.isEmpty) return;
    final targetBooks = books
        .where((b) => selectedBookIds.contains(b['id']))
        .toList();
    final removable = <String>{};
    var blockedCount = 0;
    for (final b in targetBooks) {
      if (activeLoans(b).isEmpty &&
          !reservationsOf(b).any(isActiveReservation)) {
        removable.add('${b['id']}');
      } else {
        blockedCount++;
      }
    }
    if (removable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Seçili kitaplarda ödünç/rezervasyon olduğu için silinemedi.',
          ),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seçili Kitapları Çöpe Taşı'),
        content: Text(
          '${removable.length} kitap çöp kutusuna taşınacak.${blockedCount > 0 ? '\n($blockedCount kitap ödünç/rezervasyon sebebiyle atlanacak)' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Taşı'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nowIso = DateTime.now().toIso8601String();
    final nextBooks = books
        .map(
          (b) => removable.contains(b['id']) ? {...b, 'deletedAt': nowIso} : b,
        )
        .toList();
    await save(nextBooks);
    if (mounted) {
      setState(() => selectedBookIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${removable.length} kitap çöp kutusuna taşındı.'),
        ),
      );
    }
  }
  Future<void> syncReservationNotifications(
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> after,
  ) {
    final next = _notificationQueue.then((_) async {
      try {
        await ReservationNotifications().synchronize(before, after);
      } catch (_) {
        /* Data is already stored. */
      }
      try {
        await LoanReminderService().synchronize(after);
      } catch (_) {
        /* Saved loans will be resynchronized on the next launch. */
      }
    });
    _notificationQueue = next;
    return next;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    searchController.dispose();
    _scrollParallax.dispose();
    super.dispose();
  }

  Future<void> scanCatalog() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const IsbnScannerPage(isbnOnly: false)),
    );
    if (!mounted || scanned == null) return;
    setState(() {
      searchController.text = scanned;
      query = scanned;
      tab = 1;
      selectedCategory = null;
      qualityFilter = null;
    });
  }

  Future<void> load() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      BookImageStore.instance ??= BookImageStore(
        Directory('${docs.path}/book-images'),
      );
      await AppThemeStore(docs).load();
      AiProxyStore.instance = AiProxyStore(docs);
      await AiProxyStore.instance!.load();
      final store = CatalogStore(docs);
      try {
        await ensureBundledIPhoneCatalogSeeded(
          docs,
          store,
          onProgress: (msg) {
            if (mounted) setState(() => loadingMessage = msg);
          },
        );
      } catch (_) {
        // Gömülü arşiv yüklenemezse mevcut katalog yine açılır.
      }
      final loadedDuty = await SchoolDutyStore(docs).load();
      final bundle = await store.loadBundle();
      final items = bundle.books;
      final roster = bundle.students;
      final settings = LoanSettings.fromSupplement(bundle.supplement);
      var refreshed = items;
      var refreshFailed = false;
      final next = items.map(advanceReservationQueue).toList();
      if (jsonEncode(items) != jsonEncode(next)) {
        try {
          await store.save(next);
          refreshed = next;
        } catch (_) {
          refreshFailed = true;
        }
      }
      if (mounted) {
        setState(() {
          books = refreshed;
          students = roster;
          members = bundle.members;
          loanSettings = settings;
          dutyRoster = loadedDuty;
          loading = false;
        });
        if (refreshFailed)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Rezervasyon sırası güncellenemedi; kayıtlar korundu.',
              ),
            ),
          );
      }
      unawaited(syncReservationNotifications(items, refreshed));
    } catch (_) {
      var available = false;
      try {
        final store = CatalogStore(await getApplicationDocumentsDirectory());
        available = await store.hasValidBackup();
      } catch (_) {
        // Storage itself may be unavailable; retain the error state.
      }
      if (mounted) {
        setState(() {
          backupAvailable = available;
          error = 'Katalog okunamadı. Mevcut dosya korunuyor.';
          loading = false;
        });
      }
    }
  }

  Future<void> resyncBundledIPhoneCatalog() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final docs = await getApplicationDocumentsDirectory();
      final store = CatalogStore(docs);
      final res = await ensureBundledIPhoneCatalogSeeded(
        docs,
        store,
        forceResync: true,
      );
      final bundle = await store.loadBundle();
      if (mounted) {
        setState(() {
          books = bundle.books;
          students = bundle.students;
          members = bundle.members;
          loanSettings = LoanSettings.fromSupplement(bundle.supplement);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Eşitleme tamamlandı: Toplam ${res.totalBooks} kitap (+${res.addedBooks} yeni, ${res.updatedCovers} güncellenen).',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eşitleme sırasında hata oluştu.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> recoverBackup() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final store = CatalogStore(await getApplicationDocumentsDirectory());
      final recovered = await store.restoreBackup();
      final bundle = await store.loadBundle();
      final roster = bundle.students;
      final settings = LoanSettings.fromSupplement(bundle.supplement);
      await syncReservationNotifications(books, recovered);
      if (mounted) {
        setState(() {
          books = recovered;
          students = roster;
          members = bundle.members;
          loanSettings = settings;
          error = null;
          backupAvailable = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yedek geri yüklenemedi; dosyalar korundu.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> save(List<Map<String, dynamic>> updated) async {
    if (saving) return;
    final previous = books;
    setState(() => saving = true);
    try {
      final store = CatalogStore(await getApplicationDocumentsDirectory());
      await store.save(updated);
      if (mounted) setState(() => books = updated);
      await syncReservationNotifications(previous, updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kayıt kaydedilemedi. Tekrar deneyin.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<Map<String, dynamic>?> add([
    Map<String, dynamic>? existing,
    Map<String, dynamic>? prefill,
    bool persist = true,
  ]) async {
    if (loading || saving || error != null) return null;
    final seed = existing ?? prefill;
    final title = TextEditingController(text: seed?['title'] as String?),
        author = TextEditingController(text: seed?['author'] as String?),
        isbn = TextEditingController(text: seed?['isbn'] as String?),
        shelf = TextEditingController(text: seed?['shelf'] as String?),
        publisher = TextEditingController(
          text: seed?['publisher'] as String?,
        ),
        category = TextEditingController(
          text: seed?['category'] as String?,
        ),
        series = TextEditingController(text: seed?['series'] as String?),
        year = TextEditingController(
          text: seed?['publicationYear'] as String?,
        ),
        edition = TextEditingController(text: seed?['edition'] as String?),
        pages = TextEditingController(text: seed?['pageCount'] as String?),
        notes = TextEditingController(text: seed?['notes'] as String?),
        quantity = TextEditingController(
          text: (seed?['quantity'] ?? 1).toString(),
        );
    final language = TextEditingController(
      text: seed?['language'] as String?,
    );
    final tags = TextEditingController(text: seed?['tags'] as String?);
    final readingLevel = TextEditingController(
      text: seed?['readingLevel'] as String?,
    );
    final readingStatus = TextEditingController(
      text: seed?['readingStatus'] as String?,
    );
    final contentWarning = TextEditingController(
      text: seed?['contentWarning'] as String?,
    );
    final accession = TextEditingController(
      text: seed?['accessionCode'] as String?,
    );
    final volume = TextEditingController(
      text: seed?['volume']?.toString() ?? '',
    );
    final rating = TextEditingController(
      text: seed?['rating']?.toString() ?? '',
    );
    var isTextbook = seed?['isTextbook'] == true;
    String? validationError;
    String? infoMessage;
    BookLookupSource isbnSource = BookLookupSource.auto;
    final formScroll = ScrollController();
    bool lookingUp = false;
    bool readingText = false;
    bool takingPhoto = false;
    bool cameraPermissionDenied = false;
    String? coverBase64 = seed?['coverBase64'] as String?;
    var coverRemovedManually = false;
    String? backCoverBase64 = seed?['backCoverBase64'] as String?;
    String? imprintBase64 = seed?['imprintBase64'] as String?;
    Future<void> takeBookPhoto(
      BuildContext dialogContext,
      StateSetter refresh,
    ) async {
      if (takingPhoto) return;
      final choice = await showDialog<String>(
        context: dialogContext,
        builder: (ctx) => SimpleDialog(
          title: const Text('Hangi fotoğraf çekilsin?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'cover'),
              child: const Text('Kapak'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'back'),
              child: const Text('Arka kapak'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'imprint'),
              child: const Text('Künye'),
            ),
          ],
        ),
      );
      if (choice == null || !dialogContext.mounted) return;
      refresh(() {
        takingPhoto = true;
        validationError = null;
        cameraPermissionDenied = false;
      });
      try {
        final bytes = await const MethodChannel(
          'kitapbul/camera',
        ).invokeMethod<Uint8List>('capture');
        if (!dialogContext.mounted) return;
        refresh(() {
          takingPhoto = false;
          if (bytes == null) return;
          if (bytes.length < 3 ||
              bytes.length > maxBookImageBytes ||
              bytes[0] != 0xff ||
              bytes[1] != 0xd8 ||
              bytes[2] != 0xff) {
            validationError = 'Fotoğraf okunamadı. Tekrar deneyin.';
            return;
          }
          if (choice == 'cover') coverBase64 = base64Encode(bytes);
          if (choice == 'back') backCoverBase64 = base64Encode(bytes);
          if (choice == 'imprint') imprintBase64 = base64Encode(bytes);
        });
      } on PlatformException catch (error) {
        if (dialogContext.mounted)
          refresh(() {
            takingPhoto = false;
            cameraPermissionDenied = error.code == 'permission';
            validationError = error.code == 'permission'
                ? 'Fotoğraf çekmek için kamera izni gerekli.'
                : 'Kamera açılamadı veya fotoğraf okunamadı.';
          });
      } catch (_) {
        if (dialogContext.mounted)
          refresh(() {
            takingPhoto = false;
            validationError = 'Kamera açılamadı veya fotoğraf okunamadı.';
          });
      }
    }

    Future<void> selectExtraImage(
      String kind,
      BuildContext dialogContext,
      StateSetter refresh,
    ) async {
      try {
        final bytes = await const MethodChannel(
          'kitapbul/files',
        ).invokeMethod<Uint8List>('pickCover');
        if (bytes == null || !dialogContext.mounted) return;
        final png =
            bytes.length >= 8 &&
            [
              137,
              80,
              78,
              71,
              13,
              10,
              26,
              10,
            ].asMap().entries.every((e) => bytes[e.key] == e.value);
        final jpeg =
            bytes.length >= 3 &&
            bytes[0] == 0xff &&
            bytes[1] == 0xd8 &&
            bytes[2] == 0xff;
        refresh(() {
          if (!png && !jpeg) {
            validationError = 'PNG veya JPEG görseli seçin.';
            return;
          }
          if (kind == 'back') {
            backCoverBase64 = base64Encode(bytes);
          } else {
            imprintBase64 = base64Encode(bytes);
          }
          validationError = null;
        });
      } catch (_) {
        if (dialogContext.mounted)
          refresh(
            () =>
                validationError = 'Görsel seçilemedi; 4 MB boyutunu geçmemeli.',
          );
      }
    }

    Future<void> readImageText(
      BuildContext dialogContext,
      StateSetter refresh,
    ) async {
      final sources = <String, String>{
        if (coverBase64 != null) 'Kapak': coverBase64!,
        if (backCoverBase64 != null) 'Arka kapak': backCoverBase64!,
        if (imprintBase64 != null) 'Künye': imprintBase64!,
      };
      if (sources.isEmpty || readingText) return;
      final source = await showDialog<String>(
        context: dialogContext,
        builder: (ctx) => SimpleDialog(
          title: const Text('Hangi görsel okunsun?'),
          children: [
            if (sources.length > 1)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, '__all__'),
                child: const Text('Tüm görselleri birlikte oku'),
              ),
            ...sources.keys.map(
              (name) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, name),
                child: Text(name),
              ),
            ),
          ],
        ),
      );
      if (source == null || !dialogContext.mounted) return;
      refresh(() {
        readingText = true;
        validationError = null;
      });
      try {
        final ocrPages = <OcrPage>[];
        final failures = <String>[];
        final names = source == '__all__' ? sources.keys.toList() : [source];
        for (final name in names) {
          try {
            final ocrValue = await const MethodChannel('kitapbul/ocr')
                .invokeMethod<Object>('recognize', {
                  'image':
                      bookImageBytes(sources[name]!) ??
                      (throw const FormatException('Görsel dosyası eksik')),
                });
            ocrPages.add(OcrPage(name, OcrDocument.fromPlatform(ocrValue)));
          } catch (_) {
            failures.add(name);
          }
          if (!dialogContext.mounted) return;
        }
        if (ocrPages.isEmpty)
          throw const FormatException('Görseller okunamadı');
        if (!dialogContext.mounted) return;
        refresh(() => readingText = false);
        await showDialog<void>(
          context: dialogContext,
          builder: (reviewContext) => OcrReview(
            pages: ocrPages,
            failedSources: failures,
            applySuggestions: (values) async {
              final fields = <String, TextEditingController>{
                'title': title,
                'author': author,
                'publisher': publisher,
                'isbn': isbn,
                'publicationYear': year,
                'pageCount': pages,
                'edition': edition,
              };
              var applied = 0;
              var skipped = 0;
              for (final entry in values.entries) {
                final target = fields[entry.key];
                if (target == null || target.text.trim().isNotEmpty) {
                  skipped++;
                  continue;
                }
                target.text = entry.value;
                applied++;
              }
              return '$applied alan dolduruldu${skipped > 0 ? ', $skipped dolu alan korundu' : ''}.';
            },
            applyLine: (field, value) async {
              final fields = <String, TextEditingController>{
                'title': title,
                'author': author,
                'publisher': publisher,
                'isbn': isbn,
                'publicationYear': year,
                'pageCount': pages,
                'edition': edition,
                'notes': notes,
              };
              final target = fields[field];
              if (target == null) return 'Alan bulunamadı.';
              if (field == 'publicationYear' &&
                  !RegExp(r'^(1[5-9]\d{2}|20\d{2}|2100)$').hasMatch(value))
                return 'Yalnızca dört basamaklı bir yayın yılı seçin.';
              if (field == 'pageCount' && !RegExp(r'^\d{1,5}$').hasMatch(value))
                return 'Yalnızca sayfa sayısını içeren bir satır seçin.';
              if (field == 'notes') {
                target.text = target.text.trim().isEmpty
                    ? value
                    : '${target.text.trim()}\n$value';
                return 'Satır notlara eklendi.';
              }
              if (target.text.trim().isNotEmpty &&
                  target.text.trim() != value) {
                final confirmed = await showDialog<bool>(
                  context: reviewContext,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Mevcut bilgi değişsin mi?'),
                    content: Text(
                      '“${target.text}” yerine “$value” yazılacak.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Vazgeç'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Değiştir'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !dialogContext.mounted)
                  return 'Mevcut bilgi korundu.';
              }
              target.text = value;
              return 'Satır alana aktarıldı.';
            },
          ),
        );
      } catch (_) {
        if (dialogContext.mounted)
          refresh(() {
            readingText = false;
            validationError =
                'Görseldeki metin okunamadı. Başka bir görsel deneyin.';
          });
      }
    }

    Future<void> lookupByIsbnInDialog(
      BuildContext dialogContext,
      StateSetter refresh,
    ) async {
      if (lookingUp) return;
      if (isbn.text.trim().isEmpty || !isValidIsbn(isbn.text)) {
        refresh(() {
          infoMessage = null;
          validationError = 'Önce geçerli bir ISBN girin.';
        });
        return;
      }
      final requested = isbn.text.trim();
      refresh(() {
        lookingUp = true;
        validationError = null;
        infoMessage = null;
      });
      try {
        final info = await lookupIsbn(requested, preferred: isbnSource);
        if (!dialogContext.mounted) return;
        if (isbn.text.trim() != requested) {
          refresh(() {
            lookingUp = false;
            validationError = 'ISBN değişti; yeniden arayın.';
          });
          return;
        }
        if (info == null) {
          refresh(() {
            lookingUp = false;
            validationError =
                'Bu ISBN için eşleşen kitap bulunamadı. Başlık / yazar ile Kitapyurdu aramasını deneyebilirsiniz.';
          });
          return;
        }

        Uint8List? downloadedCover;
        if (coverBase64 == null && !coverRemovedManually) {
          final coverUrl = (info['coverUrl'] ?? '').trim();
          if (coverUrl.isNotEmpty) {
            try {
              downloadedCover = await fetchCoverBytesFromUrl(coverUrl);
            } catch (_) {}
          }
          if (downloadedCover == null) {
            try {
              final best = await fetchBestCover(requested);
              downloadedCover = best?.bytes;
            } catch (_) {}
          }
        }
        if (!dialogContext.mounted) return;

        refresh(() {
          lookingUp = false;
          void fill(TextEditingController field, String key) {
            final incomingVal = (info[key] ?? '').trim();
            if (field.text.trim().isEmpty && incomingVal.isNotEmpty) {
              field.text = incomingVal;
            }
          }

          fill(title, 'title');
          fill(author, 'author');
          fill(publisher, 'publisher');
          fill(category, 'category');
          fill(year, 'publicationYear');
          fill(pages, 'pageCount');
          fill(edition, 'edition');
          fill(language, 'language');
          fill(readingLevel, 'readingLevel');
          var coverAdded = false;
          if (downloadedCover != null &&
              coverBase64 == null &&
              !coverRemovedManually) {
            coverBase64 = storeCoverBytes(downloadedCover);
            coverAdded = true;
          }
          validationError = null;
          infoMessage =
              'Bilgiler ${info['source']} üzerinden getirildi${coverAdded ? ' (kapak eklendi)' : ''}; kaydetmeden önce kontrol edin.';
        });
      } catch (_) {
        if (dialogContext.mounted) {
          refresh(() {
            lookingUp = false;
            validationError =
                'Kitap bilgisi alınamadı. İnternet bağlantısını kontrol edin.';
          });
        }
      }
    }

    Future<void> searchKitapyurduInDialog(
      BuildContext dialogContext,
      StateSetter refresh,
    ) async {
      final picked = await showDialog<FetchedBookData>(
        context: dialogContext,
        builder: (_) => KitapyurduSearchDialog(
          initialTitle: title.text.trim(),
          initialAuthor: author.text.trim(),
          initialPublisher: publisher.text.trim(),
        ),
      );
      if (picked == null || !dialogContext.mounted) return;
      final meta = picked.metadata;
      final fieldPairs = <(TextEditingController, String)>[
        (title, 'title'),
        (author, 'author'),
        (publisher, 'publisher'),
        (category, 'category'),
        (year, 'publicationYear'),
        (pages, 'pageCount'),
        (edition, 'edition'),
        (language, 'language'),
      ];
      final incomingIsbn = (meta['isbn'] ?? '').trim();
      final validIncomingIsbn =
          incomingIsbn.isNotEmpty && isValidIsbn(incomingIsbn);

      var hasConflict = false;
      for (final (controller, key) in fieldPairs) {
        final cur = controller.text.trim();
        final next = (meta[key] ?? '').trim();
        if (cur.isNotEmpty &&
            next.isNotEmpty &&
            foldTurkish(cur) != foldTurkish(next)) {
          hasConflict = true;
          break;
        }
      }
      if (!hasConflict &&
          validIncomingIsbn &&
          isbn.text.trim().isNotEmpty &&
          canonicalIsbn(isbn.text) != canonicalIsbn(incomingIsbn)) {
        hasConflict = true;
      }

      var overwriteExisting = false;
      if (hasConflict && dialogContext.mounted) {
        final choice = await showDialog<bool>(
          context: dialogContext,
          builder: (confirmCtx) => AlertDialog(
            title: const Text('Dolu alanlar güncellensin mi?'),
            content: const Text(
              'Formdaki bazı alanlar zaten dolu. Yalnız boş alanlar doldurulsun mu, yoksa mevcut bilgiler de Kitapyurdu verileriyle değiştirilsin mi?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(confirmCtx, false),
                child: const Text('Yalnız boşları doldur'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(confirmCtx, true),
                child: const Text('Tümünü güncelle'),
              ),
            ],
          ),
        );
        if (!dialogContext.mounted) return;
        overwriteExisting = choice == true;
      }

      refresh(() {
        for (final (controller, key) in fieldPairs) {
          final next = (meta[key] ?? '').trim();
          if (next.isEmpty) continue;
          if (overwriteExisting || controller.text.trim().isEmpty) {
            controller.text = next;
          }
        }
        if (validIncomingIsbn &&
            (overwriteExisting || isbn.text.trim().isEmpty)) {
          isbn.text = cleanIsbnInput(incomingIsbn);
        }
        var coverAdded = false;
        if (picked.coverBytes != null &&
            (overwriteExisting ||
                (coverBase64 == null && !coverRemovedManually))) {
          coverBase64 = storeCoverBytes(picked.coverBytes!);
          coverRemovedManually = false;
          coverAdded = true;
        }
        validationError = null;
        infoMessage =
            'Bilgiler Kitapyurdu üzerinden aktarıldı${coverAdded ? ' (kapak eklendi)' : ''}; kaydetmeden önce kontrol edin.';
      });
    }

    final shelfSuggestions = topFieldSuggestions(books, 'shelf', limit: 8);
    final categorySuggestions = topFieldSuggestions(
      books,
      'category',
      limit: 6,
    );
    final accCfg = appThemeNotifier.value;

    Future<void> submitForm(BuildContext ctx, StateSetter refresh) async {
      if (title.text.trim().isNotEmpty &&
          (volume.text.trim().isEmpty ||
              (int.tryParse(volume.text.trim()) != null &&
                  int.parse(volume.text.trim()) >= 0)) &&
          (rating.text.trim().isEmpty ||
              (int.tryParse(rating.text.trim()) != null &&
                  int.parse(rating.text.trim()) >= 0 &&
                  int.parse(rating.text.trim()) <= 5)) &&
          isAcceptableIsbnEdit(isbn.text, existing?['isbn'] as String?) &&
          (int.tryParse(quantity.text) ?? 0) >=
              (existing == null
                  ? 1
                  : (minimumCopyQuantity(existing) > 0
                        ? minimumCopyQuantity(existing)
                        : 1))) {
        final isbnKey = canonicalIsbn(isbn.text);
        final duplicates = isbnKey == null
            ? <Map<String, dynamic>>[]
            : books
                  .where(
                    (b) =>
                        b['deletedAt'] == null &&
                        b['id'] != existing?['id'] &&
                        canonicalIsbn((b['isbn'] ?? '').toString()) == isbnKey,
                  )
                  .toList();
        final incoming = <String, dynamic>{
          'title': title.text.trim(),
          'author': author.text.trim(),
          'isbn': isbn.text.trim(),
          'shelf': shelf.text.trim(),
          'publisher': publisher.text.trim(),
          'category': category.text.trim(),
          'series': series.text.trim(),
          'language': language.text.trim(),
          'tags': tags.text.trim(),
          'readingLevel': readingLevel.text.trim(),
          'readingStatus': readingStatus.text.trim(),
          'contentWarning': contentWarning.text.trim(),
          'accessionCode': accession.text.trim(),
          'volume': int.tryParse(volume.text.trim()),
          'rating': int.tryParse(rating.text.trim()),
          'publicationYear': year.text.trim(),
          'edition': edition.text.trim(),
          'pageCount': pages.text.trim(),
          'notes': notes.text.trim(),
          'coverBase64': coverBase64,
          if (coverRemovedManually ||
              (existing != null && coverBase64 != existing['coverBase64']))
            'coverAutoLocked': true,
          'backCoverBase64': backCoverBase64,
          'imprintBase64': imprintBase64,
          'quantity': int.parse(quantity.text),
          'isTextbook': isTextbook,
        };
        if (duplicates.isNotEmpty) {
          final choice = await showDialog<String>(
            context: ctx,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Bu ISBN zaten kayıtlı'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ayrı kayıt oluşturabilir veya uyumlu bir kayda nüsha ekleyebilirsiniz.',
                    ),
                    ...duplicates.map(
                      (b) => ListTile(
                        title: Text(b['title']),
                        subtitle: Text(
                          '${b['author']} · ${b['quantity']} nüsha',
                        ),
                        trailing:
                            existing == null && canMergeCopies(incoming, b)
                            ? TextButton(
                                onPressed: () => Navigator.pop(
                                  dialogContext,
                                  'merge:${b['id']}',
                                ),
                                child: const Text('Nüsha ekle'),
                              )
                            : const Text('Ayrı baskı'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Düzenlemeye dön'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, 'separate'),
                  child: const Text('Ayrı kaydet'),
                ),
              ],
            ),
          );
          if (choice == null || !ctx.mounted) return;
          if (choice.startsWith('merge:')) {
            Navigator.pop(ctx, {
              'mergeTarget': choice.substring(6),
              'incoming': incoming,
            });
            return;
          }
        }
        if (!ctx.mounted) return;
        Navigator.pop(ctx, {
          ...?existing,
          'id':
              existing?['id'] ??
              DateTime.now().microsecondsSinceEpoch.toString(),
          'title': title.text.trim(),
          'author': author.text.trim(),
          'isbn': isbn.text.trim(),
          'shelf': shelf.text.trim(),
          'publisher': publisher.text.trim(),
          'category': category.text.trim(),
          'series': series.text.trim(),
          'language': language.text.trim(),
          'tags': tags.text.trim(),
          'readingLevel': readingLevel.text.trim(),
          'readingStatus': readingStatus.text.trim(),
          'contentWarning': contentWarning.text.trim(),
          'accessionCode': accession.text.trim(),
          'volume': int.tryParse(volume.text.trim()),
          'rating': int.tryParse(rating.text.trim()),
          'publicationYear': year.text.trim(),
          'edition': edition.text.trim(),
          'pageCount': pages.text.trim(),
          'notes': notes.text.trim(),
          'coverBase64': coverBase64,
          if (coverRemovedManually ||
              (existing != null && coverBase64 != existing['coverBase64']))
            'coverAutoLocked': true,
          'backCoverBase64': backCoverBase64,
          'imprintBase64': imprintBase64,
          'quantity': int.parse(quantity.text),
          'isTextbook': isTextbook,
          'loans': existing?['loans'] ?? <Map<String, dynamic>>[],
        });
      } else {
        refresh(
          () => validationError =
              !isAcceptableIsbnEdit(isbn.text, existing?['isbn'] as String?)
              ? 'ISBN geçerli değil. 10 veya 13 haneli ISBN girin.'
              : 'Kitap adı ve geçerli nüsha sayısı gerekli; cilt 0 veya üzeri, puan 0 ile 5 arasında olmalı.',
        );
      }
    }

    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          final isWide = MediaQuery.sizeOf(ctx).width >= 680;
          final currentRating =
              (int.tryParse(rating.text.trim()) ?? 0).clamp(0, 5);
          final minQty = existing == null
              ? 1
              : (minimumCopyQuantity(existing) > 0
                    ? minimumCopyQuantity(existing)
                    : 1);

          return Dialog(
            insetPadding: isWide
                ? const EdgeInsets.symmetric(horizontal: 40, vertical: 24)
                : EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isWide ? 24 : 0),
            ),
            child: ConstrainedBox(
              constraints: isWide
                  ? const BoxConstraints(maxWidth: 680, maxHeight: 860)
                  : const BoxConstraints(),
              child: Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    tooltip: 'Vazgeç',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  title: Text(
                    existing == null ? 'Kitap Ekle' : 'Kitabı Düzenle',
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: FilledButton.icon(
                        onPressed: () => submitForm(ctx, refresh),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Kaydet'),
                      ),
                    ),
                  ],
                ),
                body: Scrollbar(
                  controller: formScroll,
                  thumbVisibility: true,
                  child: ListView(
                    controller: formScroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                    children: [
                      if (validationError != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.errorContainer.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            validationError!,
                            style: TextStyle(
                              color: Theme.of(
                                ctx,
                              ).colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (infoMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.primaryContainer.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            infoMessage!,
                            style: TextStyle(
                              color: Theme.of(
                                ctx,
                              ).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (cameraPermissionDenied)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await const MethodChannel(
                                  'kitapbul/camera',
                                ).invokeMethod<bool>('settings');
                              } catch (_) {
                                if (ctx.mounted) {
                                  refresh(
                                    () => validationError =
                                        'Uygulama ayarları açılamadı.',
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.settings_rounded),
                            label: const Text('Kamera izni ayarları'),
                          ),
                        ),

                      BookEditorSectionCard(
                        icon: Icons.photo_library_outlined,
                        title: 'Kapak, Arka Kapak & Künye Fotoğrafları',
                        children: [
                          if (coverBase64 != null ||
                              backCoverBase64 != null ||
                              imprintBase64 != null) ...[
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  if (coverBase64 != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: Column(
                                        children: [
                                          coverThumbnail({
                                            'coverBase64': coverBase64,
                                          }),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Ön Kapak',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (backCoverBase64 != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: Column(
                                        children: [
                                          coverThumbnail({
                                            'coverBase64': backCoverBase64,
                                          }),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Arka Kapak',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (imprintBase64 != null)
                                    Column(
                                      children: [
                                        coverThumbnail({
                                          'coverBase64': imprintBase64,
                                        }),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Künye',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: takingPhoto
                                    ? null
                                    : () => takeBookPhoto(ctx, refresh),
                                icon: const Icon(
                                  Icons.photo_camera_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  takingPhoto ? 'Kamera açık…' : 'Fotoğraf Çek',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    final selected = await const MethodChannel(
                                      'kitapbul/files',
                                    ).invokeMethod<Uint8List>('pickCover');
                                    if (selected == null || !ctx.mounted) {
                                      return;
                                    }
                                    final png =
                                        selected.length >= 8 &&
                                        [137, 80, 78, 71, 13, 10, 26, 10]
                                            .asMap()
                                            .entries
                                            .every(
                                              (e) => selected[e.key] == e.value,
                                            );
                                    final jpeg =
                                        selected.length >= 3 &&
                                        selected[0] == 0xff &&
                                        selected[1] == 0xd8 &&
                                        selected[2] == 0xff;
                                    refresh(() {
                                      if (!png && !jpeg) {
                                        validationError =
                                            'PNG veya JPEG görseli seçin.';
                                        return;
                                      }
                                      coverBase64 = base64Encode(selected);
                                      validationError = null;
                                    });
                                  } catch (_) {
                                    if (ctx.mounted) {
                                      refresh(
                                        () => validationError =
                                            'Kapak seçilemedi; görsel 4 MB boyutunu geçmemeli.',
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(
                                  Icons.image_outlined,
                                  size: 18,
                                ),
                                label: const Text('Kapak Seç'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    selectExtraImage('back', ctx, refresh),
                                icon: const Icon(
                                  Icons.flip_to_back_rounded,
                                  size: 18,
                                ),
                                label: const Text('Arka Kapak'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    selectExtraImage('imprint', ctx, refresh),
                                icon: const Icon(
                                  Icons.article_outlined,
                                  size: 18,
                                ),
                                label: const Text('Künye Görseli'),
                              ),
                              if (coverBase64 != null ||
                                  backCoverBase64 != null ||
                                  imprintBase64 != null)
                                FilledButton.tonalIcon(
                                  onPressed: readingText
                                      ? null
                                      : () => readImageText(ctx, refresh),
                                  icon: const Icon(
                                    Icons.text_snippet_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    readingText
                                        ? 'Metin okunuyor…'
                                        : 'Görselden Metin Oku',
                                  ),
                                ),
                              if (coverBase64 != null)
                                TextButton(
                                  onPressed: () => refresh(() {
                                    coverBase64 = null;
                                    coverRemovedManually = true;
                                  }),
                                  child: const Text('Kapağı Kaldır'),
                                ),
                              if (backCoverBase64 != null)
                                TextButton(
                                  onPressed: () =>
                                      refresh(() => backCoverBase64 = null),
                                  child: const Text('Arka Kapağı Kaldır'),
                                ),
                              if (imprintBase64 != null)
                                TextButton(
                                  onPressed: () =>
                                      refresh(() => imprintBase64 = null),
                                  child: const Text('Künye Görselini Kaldır'),
                                ),
                            ],
                          ),
                        ],
                      ),

                      BookEditorSectionCard(
                        icon: Icons.menu_book_rounded,
                        title: 'Temel Bilgiler & ISBN Arama',
                        children: [
                          TextField(
                            controller: title,
                            decoration: bookFieldDecoration('Kitap adı *'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: author,
                            decoration: bookFieldDecoration('Yazar'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: isbn,
                            keyboardType: TextInputType.text,
                            decoration: bookFieldDecoration(
                              'ISBN',
                              suffixIcon: IconButton(
                                tooltip: 'ISBN barkodu tara',
                                icon: const Icon(Icons.qr_code_scanner),
                                onPressed: () async {
                                  final value = await Navigator.of(ctx)
                                      .push<String>(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const IsbnScannerPage(),
                                        ),
                                      );
                                  if (value != null && ctx.mounted) {
                                    isbn.text = value;
                                    if (isValidIsbn(value)) {
                                      await lookupByIsbnInDialog(ctx, refresh);
                                    }
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<BookLookupSource>(
                            initialValue: isbnSource,
                            isExpanded: true,
                            decoration: bookFieldDecoration(
                              'ISBN veri kaynağı',
                            ),
                            items: [
                              for (final s in BookLookupSource.values)
                                DropdownMenuItem(
                                  value: s,
                                  child: Text(s.label),
                                ),
                            ],
                            onChanged: lookingUp
                                ? null
                                : (v) {
                                    if (v != null) {
                                      refresh(() => isbnSource = v);
                                    }
                                  },
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: lookingUp
                                    ? null
                                    : () => lookupByIsbnInDialog(ctx, refresh),
                                icon: lookingUp
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.search, size: 18),
                                label: Text(
                                  lookingUp
                                      ? 'Aranıyor…'
                                      : 'ISBN ile Bilgileri Getir',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: lookingUp
                                    ? null
                                    : () =>
                                          searchKitapyurduInDialog(ctx, refresh),
                                icon: const Icon(
                                  Icons.travel_explore_outlined,
                                  size: 18,
                                ),
                                label: const Text('Kitapyurdu\'ndan Ara'),
                              ),
                            ],
                          ),
                        ],
                      ),

                      BookEditorSectionCard(
                        icon: Icons.shelves,
                        title: 'Dolap / Raf, Stok & Demirbaş',
                        children: [
                          TextField(
                            controller: shelf,
                            decoration: bookFieldDecoration('Dolap / raf'),
                          ),
                          if (shelfSuggestions.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final s in shelfSuggestions)
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      s.length <= 2 ? 'Dolap $s' : s,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    onPressed: () =>
                                        refresh(() => shelf.text = s),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: quantity,
                                  keyboardType: TextInputType.number,
                                  decoration: bookFieldDecoration(
                                    'Nüsha sayısı',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: 'Nüsha azalt',
                                onPressed: () {
                                  final cur =
                                      int.tryParse(quantity.text.trim()) ?? 1;
                                  if (cur > minQty) {
                                    refresh(
                                      () => quantity.text = '${cur - 1}',
                                    );
                                  }
                                },
                                icon: const Icon(Icons.remove_rounded),
                              ),
                              const SizedBox(width: 4),
                              IconButton.filledTonal(
                                tooltip: 'Nüsha artır',
                                onPressed: () {
                                  final cur =
                                      int.tryParse(quantity.text.trim()) ?? 1;
                                  refresh(() => quantity.text = '${cur + 1}');
                                },
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: accession,
                            decoration: bookFieldDecoration(
                              'Demirbaş kodu',
                              suffixIcon: TextButton(
                                onPressed: () {
                                  final nextNum =
                                      findHighestAccessionNumber(
                                        books,
                                        prefix: accCfg.accessionPrefix,
                                      ) +
                                      1;
                                  final code =
                                      '${accCfg.accessionPrefix}${nextNum.toString().padLeft(accCfg.accessionDigits, '0')}';
                                  refresh(() => accession.text = code);
                                },
                                child: const Text('Oto Kod'),
                              ),
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Ders kitabı'),
                            value: isTextbook,
                            onChanged: (v) => refresh(() => isTextbook = v),
                          ),
                        ],
                      ),

                      BookEditorSectionCard(
                        icon: Icons.category_outlined,
                        title: 'Kategori, Puanlama & Okuma Durumu',
                        children: [
                          TextField(
                            controller: category,
                            decoration: bookFieldDecoration('Kategori'),
                          ),
                          if (categorySuggestions.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final c in categorySuggestions)
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      c,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    onPressed: () =>
                                        refresh(() => category.text = c),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Text(
                                'Değerlendirme:',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 10),
                              StarRatingRow(
                                rating: currentRating,
                                size: 24,
                                showNumeric: true,
                                onChanged: (val) => refresh(
                                  () => rating.text = val == 0 ? '' : '$val',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: readingStatus,
                            decoration: bookFieldDecoration('Okuma durumu'),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final st in const [
                                'Okunmadı',
                                'Okunuyor',
                                'Okundu',
                                'Önerilen',
                              ])
                                ChoiceChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    st,
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  selected:
                                      readingStatus.text.trim().toLowerCase() ==
                                      st.toLowerCase(),
                                  onSelected: (sel) => refresh(
                                    () => readingStatus.text = sel ? st : '',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),

                      BookEditorSectionCard(
                        icon: Icons.info_outline_rounded,
                        title: 'Detaylı Künye, Etiketler & Notlar',
                        children: [
                          TextField(
                            controller: publisher,
                            decoration: bookFieldDecoration('Yayınevi'),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: series,
                                  decoration: bookFieldDecoration('Seri'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: volume,
                                  keyboardType: TextInputType.number,
                                  decoration: bookFieldDecoration('Cilt no'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: year,
                                  keyboardType: TextInputType.number,
                                  decoration: bookFieldDecoration('Yayın yılı'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: pages,
                                  keyboardType: TextInputType.number,
                                  decoration: bookFieldDecoration(
                                    'Sayfa sayısı',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: edition,
                                  decoration: bookFieldDecoration('Baskı'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: language,
                                  decoration: bookFieldDecoration('Dil'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: tags,
                            decoration: bookFieldDecoration(
                              'Etiketler (virgül ile ayırın)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: readingLevel,
                            decoration: bookFieldDecoration('Okuma düzeyi'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: contentWarning,
                            maxLines: 2,
                            decoration: bookFieldDecoration('İçerik uyarısı'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: notes,
                            maxLines: 3,
                            decoration: bookFieldDecoration('Notlar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    Map<String, dynamic>? savedBook;
    if (data != null && data['mergeTarget'] != null) {
      final target = data['mergeTarget'];
      final incoming = Map<String, dynamic>.from(data['incoming'] as Map);
      final nextBooks = books.map((book) {
        if (book['id'] == target) {
          final merged = mergeCopies(incoming, book);
          savedBook = merged;
          return merged;
        }
        return book;
      }).toList();
      if (persist) {
        await save(nextBooks);
      }
    } else if (data != null) {
      savedBook = data;
      if (persist) {
        await save(
          existing == null
              ? [...books, data]
              : books.map((b) => b['id'] == existing['id'] ? data : b).toList(),
        );
      }
    }
    title.dispose();
    author.dispose();
    isbn.dispose();
    shelf.dispose();
    quantity.dispose();
    publisher.dispose();
    category.dispose();
    series.dispose();
    year.dispose();
    edition.dispose();
    pages.dispose();
    notes.dispose();
    language.dispose();
    tags.dispose();
    readingLevel.dispose();
    readingStatus.dispose();
    contentWarning.dispose();
    accession.dispose();
    volume.dispose();
    rating.dispose();
    formScroll.dispose();
    return savedBook;
  }

  Future<void> importStudentsCsv() async {
    if (saving) return;
    try {
      final bytes = await const MethodChannel(
        'kitapbul/files',
      ).invokeMethod<Uint8List>('pickStudentsCsv');
      if (bytes == null || !mounted) return;
      final rows = parseStudentCsv(bytes);
      final width = rows.fold<int>(
        0,
        (a, row) => row.length > a ? row.length : a,
      );
      var nameColumn = 0, numberColumn = -1, classColumn = -1;
      var header = true;
      var updateMatches = false;
      final labels = rows.first.map((s) => s.toLowerCase()).toList();
      for (var i = 0; i < labels.length; i++) {
        final label = labels[i];
        if (label.contains('numara') || label == 'no' || label == 'number')
          numberColumn = i;
        else if (label.contains('sınıf') ||
            label.contains('sinif') ||
            label.contains('şube') ||
            label == 'class')
          classColumn = i;
        else if (label.contains('ad') ||
            label.contains('isim') ||
            label == 'name')
          nameColumn = i;
      }
      final selected = await showDialog<StudentCsvPreview>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, refresh) {
            StudentCsvPreview? preview;
            try {
              preview = previewStudentCsv(
                rows,
                students,
                nameColumn: nameColumn,
                numberColumn: numberColumn,
                classColumn: classColumn,
                header: header,
                updateMatches: updateMatches,
              );
            } on FormatException {
              /* displayed below */
            }
            List<DropdownMenuItem<int>> options(bool optional) => [
              if (optional)
                const DropdownMenuItem(value: -1, child: Text('Yok')),
              for (var i = 0; i < width; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    'Sütun ${i + 1}: ${i < rows.first.length ? rows.first[i] : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ];
            return AlertDialog(
              title: const Text('Öğrenci CSV aktarımı'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: const Text('İlk satır başlık'),
                        value: header,
                        onChanged: (v) => refresh(() => header = v),
                      ),
                      SwitchListTile(
                        title: const Text(
                          'Tek numara eşleşmesinde öğrenciyi güncelle',
                        ),
                        value: updateMatches,
                        onChanged: (v) => refresh(() => updateMatches = v),
                      ),
                      DropdownButtonFormField<int>(
                        initialValue: nameColumn,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Ad soyad',
                        ),
                        items: options(false),
                        onChanged: (v) => refresh(() => nameColumn = v!),
                      ),
                      DropdownButtonFormField<int>(
                        initialValue: numberColumn,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Numara'),
                        items: options(true),
                        onChanged: (v) => refresh(() => numberColumn = v!),
                      ),
                      DropdownButtonFormField<int>(
                        initialValue: classColumn,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Sınıf'),
                        items: options(true),
                        onChanged: (v) => refresh(() => classColumn = v!),
                      ),
                      const SizedBox(height: 16),
                      if (preview == null)
                        const Text('Her alan için farklı bir sütun seçin.')
                      else ...[
                        Text(
                          '${preview.students.length} öğrenci eklenecek, ${preview.afterUpdates.length} öğrenci güncellenecek, ${preview.skipped} boş veya eşleşen satır atlanacak.',
                        ),
                        const Text(
                          'Güncellenen öğrencilerin kimlikleri korunur. Önceki liste yerel yedekte korunur.',
                        ),
                        ...preview.students
                            .take(20)
                            .map(
                              (s) => Text(
                                '${s.name} · ${s.number} · ${s.className}',
                              ),
                            ),
                        if (preview.students.length > 20)
                          const Text('İlk 20 öğrenci gösteriliyor.'),
                        ...preview.afterUpdates.take(20).map((s) {
                          final old = preview!.beforeUpdates.firstWhere(
                            (item) => item.id == s.id,
                          );
                          return Text(
                            'Güncelle: ${old.name} · ${old.className} → ${s.name} · ${s.className} (${s.number})',
                          );
                        }),
                        if (preview.issues.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('Atlanacak satırlar:'),
                          ...preview.issues
                              .take(20)
                              .map((issue) => Text(issue)),
                          if (preview.issues.length > 20)
                            const Text('İlk 20 sorun gösteriliyor.'),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed:
                      preview == null ||
                          (preview.students.isEmpty &&
                              preview.afterUpdates.isEmpty)
                      ? null
                      : () => Navigator.pop(ctx, preview),
                  child: const Text('Öğrencileri aktar'),
                ),
              ],
            );
          },
        ),
      );
      if (selected == null || !mounted) return;
      setState(() => saving = true);
      final replacements = {for (final s in selected.afterUpdates) s.id: s};
      final updated = [
        ...students.map((s) => replacements[s.id] ?? s),
        ...selected.students,
      ];
      final updatedBooks = syncStudentLoans(books, selected.afterUpdates);
      await CatalogStore(await getApplicationDocumentsDirectory()).save(
        updatedBooks,
        students: updated,
        importReceipt: StudentImportReceipt(
          before: selected.beforeUpdates,
          after: [...selected.students, ...selected.afterUpdates],
        ),
      );
      if (mounted) {
        setState(() {
          students = updated;
          books = updatedBooks;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${selected.students.length} öğrenci eklendi, ${selected.afterUpdates.length} öğrenci güncellendi.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'CSV okunamadı veya kaydedilemedi. UTF-8 biçimini kontrol edin.',
            ),
          ),
        );
    } finally {
      if (mounted && saving) setState(() => saving = false);
    }
  }

  Future<void> undoStudentCsvImport() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final store = CatalogStore(await getApplicationDocumentsDirectory());
      final receipt = await store.loadStudentImportReceipt();
      if (!mounted) return;
      if (receipt == null || receipt.after.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geri alınabilecek öğrenci aktarımı yok.'),
          ),
        );
        return;
      }
      final ids = receipt.after.map((s) => s.id).toSet();
      if (!canUndoStudentImport(receipt, students, books)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aktarılan kayıtlar değişmiş veya ödünç geçmişinde kullanılmış; geri alma yapılmadı.',
            ),
          ),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Son öğrenci aktarımını geri al'),
          content: Text(
            '${receipt.after.length - receipt.before.length} öğrenci kaldırılacak, ${receipt.before.length} öğrenci önceki bilgilerine dönecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Geri al'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final prior = {for (final s in receipt.before) s.id: s};
      final updated = students
          .where((s) => !ids.contains(s.id) || prior.containsKey(s.id))
          .map((s) => prior[s.id] ?? s)
          .toList();
      final updatedBooks = syncStudentLoans(books, receipt.before);
      await store.save(
        updatedBooks,
        students: updated,
        clearImportReceipt: true,
      );
      if (mounted) {
        setState(() {
          students = updated;
          books = updatedBooks;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Son öğrenci aktarımı geri alındı.')),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Öğrenci aktarımı geri alınamadı.')),
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> promoteStudents() async {
    var finalGrade = 8;
    final plan = await showDialog<List<PromotionChange>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          final changes = planPromotion(students, finalGrade);
          return AlertDialog(
            title: const Text('Sınıf atlatma'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: finalGrade,
                      decoration: const InputDecoration(
                        labelText: 'Son kademe',
                      ),
                      items: [
                        for (var i = 4; i <= 12; i++)
                          DropdownMenuItem(value: i, child: Text('$i. sınıf')),
                      ],
                      onChanged: (v) => refresh(() => finalGrade = v!),
                    ),
                    Text(
                      '${changes.length} öğrenci değişecek; son kademedekiler mezun listesine alınır.',
                    ),
                    ...changes
                        .take(200)
                        .map(
                          (c) => Text(
                            '${c.before.name}: ${c.before.className} → ${c.next ?? 'Mezun'}',
                          ),
                        ),
                    if (changes.length > 200)
                      const Text('İlk 200 öğrenci gösteriliyor.'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: changes.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, changes),
                child: const Text('Devam'),
              ),
            ],
          );
        },
      ),
    );
    if (plan == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sınıf atlatmayı uygula'),
        content: Text(
          '${plan.length} öğrenci güncellenecek. Önceki kayıtlar yerel yedekte korunacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || saving) return;
    setState(() => saving = true);
    try {
      final result = applyPromotion(students, books, plan);
      await CatalogStore(
        await getApplicationDocumentsDirectory(),
      ).save(result.books, students: result.students, clearImportReceipt: true);
      if (mounted) {
        setState(() {
          books = result.books;
          students = result.students;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sınıf atlatma tamamlandı.')),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sınıf atlatma kaydedilemedi; kayıtlar korundu.'),
          ),
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> showGraduates() async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, refresh) => AlertDialog(
          title: const Text('Mezunlar'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!students.any((s) => s.graduatedAt != null))
                    const Text('Mezun kaydı yok.'),
                  ...students
                      .where((s) => s.graduatedAt != null)
                      .map(
                        (student) => ListTile(
                          onTap: () => Navigator.of(dialog).push(
                            MaterialPageRoute(
                              builder: (_) => StudentProfilePage(
                                student: student,
                                books: books,
                              ),
                            ),
                          ),
                          title: Text(student.name),
                          subtitle: Text(
                            '${student.number} · ${student.className}',
                          ),
                          trailing: TextButton(
                            child: const Text('Geri çağır'),
                            onPressed: () async {
                              var className = student.className;
                              final chosen = await showDialog<String>(
                                context: dialog,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Öğrenciyi geri çağır'),
                                  content: TextFormField(
                                    initialValue: className,
                                    decoration: const InputDecoration(
                                      labelText: 'Sınıf',
                                    ),
                                    onChanged: (v) => className = v,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Vazgeç'),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        if (className.trim().isNotEmpty)
                                          Navigator.pop(ctx, className.trim());
                                      },
                                      child: const Text('Geri çağır'),
                                    ),
                                  ],
                                ),
                              );
                              if (chosen == null || !mounted || saving) return;
                              final restored = Student(
                                id: student.id,
                                name: student.name,
                                number: student.number,
                                className: chosen,
                              );
                              final updated = students
                                  .map((s) => s.id == student.id ? restored : s)
                                  .toList();
                              final updatedBooks = syncStudentLoans(books, [
                                restored,
                              ]);
                              setState(() => saving = true);
                              try {
                                await CatalogStore(
                                  await getApplicationDocumentsDirectory(),
                                ).save(
                                  updatedBooks,
                                  students: updated,
                                  clearImportReceipt: true,
                                );
                                if (mounted) {
                                  setState(() {
                                    students = updated;
                                    books = updatedBooks;
                                  });
                                  if (dialog.mounted) refresh(() {});
                                }
                              } catch (_) {
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Mezun geri çağrılamadı.'),
                                    ),
                                  );
                              } finally {
                                if (mounted) setState(() => saving = false);
                              }
                            },
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Kapat'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showStudents() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentsDirectoryPage(
          initialStudents: students,
          initialMembers: members,
          initialBooks: books,
          onPersist: (nextBooks, nextStudents, nextMembers) async {
            try {
              await CatalogStore(
                await getApplicationDocumentsDirectory(),
              ).save(
                nextBooks,
                students: nextStudents,
                members: nextMembers,
              );
              if (mounted) {
                setState(() {
                  books = nextBooks;
                  students = nextStudents;
                  members = nextMembers;
                });
              }
              return true;
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Kayıt güncellenemedi.')),
                );
              }
              return false;
            }
          },
          onImportCsv: importStudentsCsv,
          onUndoImport: undoStudentCsvImport,
          onPromote: promoteStudents,
          onShowGraduates: showGraduates,
          readLatestState: () => (
            books: books,
            students: students,
            members: members,
          ),
        ),
      ),
    );
  }

  Future<bool> confirmDuplicateLoan(
    Map<String, dynamic> book,
    Map<String, dynamic> borrower,
  ) async {
    if (!hasDuplicateBorrower(book, borrower)) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kitap zaten ödünçte'),
            content: Text(
              '${borrower['name']} “${book['title']}” kitabını zaten ödünç aldı. İkinci nüshayı da vermek istiyor musunuz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Yine de ver'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> loan(Map<String, dynamic> book) async {
    if (saving) return;
    final refreshed = advanceReservationQueue(book);
    if (jsonEncode(reservationsOf(refreshed)) !=
        jsonEncode(reservationsOf(book))) {
      await save(
        books.map((b) => b['id'] == book['id'] ? refreshed : b).toList(),
      );
      if (!mounted) return;
      book = books.firstWhere((b) => b['id'] == book['id']);
    }
    if (availableCopies(book) <= 0) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Uygun nüsha yok; rezervasyon sırasını kontrol edin.',
            ),
          ),
        );
      return;
    }
    final name = TextEditingController();
    final studentClass = TextEditingController();
    String? studentId;
    String? memberId;
    final copies = ((book['copies'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    final usedCopies = {
      for (final l in activeLoans(book))
        if (l['copyId'] is String) (l['copyId'] as String).toUpperCase(),
    };
    final heldCopies = {
      for (final r in reservationsOf(book))
        if (isReadyReservation(r) && r['copyId'] is String)
          (r['copyId'] as String).toUpperCase(),
    };
    final available = copies
        .where(
          (copy) =>
              copy['status'] == 'Rafta' &&
              !usedCopies.contains((copy['id'] as String).toUpperCase()) &&
              !heldCopies.contains((copy['id'] as String).toUpperCase()),
        )
        .toList();
    final trackedLost = copies.where((c) => c['status'] == 'Kayıp').length;
    final untrackedAvailable =
        (book['quantity'] as int) -
        copies.length -
        activeLoans(book).where((l) => l['copyId'] == null).length -
        (((book['lostCount'] as int?) ?? 0) - trackedLost) -
        reservationsOf(
          book,
        ).where((r) => isReadyReservation(r) && r['copyId'] == null).length;
    var copyChoice = 'auto';
    DateTime due = DateTime.now().add(Duration(days: loanSettings.days));
    var dueManuallySet = false;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('Ödünç ver'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (students.any((s) => s.graduatedAt == null))
                  TextButton.icon(
                    icon: const Icon(Icons.person_search),
                    label: const Text('Kayıtlı öğrenci seç'),
                    onPressed: () async {
                      final chosen = await showDialog<Student>(
                        context: ctx,
                        builder: (dialog) => SimpleDialog(
                          title: const Text('Öğrenci seç'),
                          children: students
                              .where((s) => s.graduatedAt == null)
                              .map(
                                (s) => SimpleDialogOption(
                                  onPressed: () => Navigator.pop(dialog, s),
                                  child: Text(
                                    '${s.name} · ${s.className} · ${s.number}',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      );
                      if (chosen != null)
                        refresh(() {
                          name.text = chosen.name;
                          studentClass.text = chosen.className;
                          studentId = chosen.id;
                          memberId = null;
                          if (!dueManuallySet)
                            due = DateTime.now().add(
                              Duration(
                                days: loanSettings.durationFor(
                                  chosen.className,
                                ),
                              ),
                            );
                        });
                    },
                  ),
                if (students.any((s) => s.graduatedAt == null))
                  TextButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Öğrenci kartını tara'),
                    onPressed: () async {
                      final code = await Navigator.of(ctx).push<String>(
                        MaterialPageRoute(
                          builder: (_) => const IsbnScannerPage(
                            isbnOnly: false,
                            studentCard: true,
                          ),
                        ),
                      );
                      if (code == null || !ctx.mounted) return;
                      try {
                        final chosen = resolveStudentCard(code, students);
                        refresh(() {
                          name.text = chosen.name;
                          studentClass.text = chosen.className;
                          studentId = chosen.id;
                          memberId = null;
                          if (!dueManuallySet)
                            due = DateTime.now().add(
                              Duration(
                                days: loanSettings.durationFor(
                                  chosen.className,
                                ),
                              ),
                            );
                        });
                      } on FormatException catch (e) {
                        if (ctx.mounted)
                          ScaffoldMessenger.of(
                            ctx,
                          ).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    },
                  ),
                if (members.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.people),
                    label: const Text('Kayıtlı üye seç'),
                    onPressed: () async {
                      final chosen = await showDialog<Member>(
                        context: ctx,
                        builder: (dialog) => SimpleDialog(
                          title: const Text('Üye seç'),
                          children: members
                              .map(
                                (m) => SimpleDialogOption(
                                  onPressed: () => Navigator.pop(dialog, m),
                                  child: Text(
                                    '${m.name} · ${m.kindTitle} · ${m.number}',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      );
                      if (chosen != null)
                        refresh(() {
                          name.text = chosen.name;
                          studentClass.text = '';
                          studentId = null;
                          memberId = chosen.id;
                          if (!dueManuallySet)
                            due = DateTime.now().add(
                              Duration(
                                days:
                                    loanSettings
                                        .memberRuleFor(chosen.kind)
                                        ?.days ??
                                    loanSettings.days,
                              ),
                            );
                        });
                    },
                  ),
                TextField(
                  controller: name,
                  onChanged: (_) {
                    studentId = null;
                    memberId = null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Öğrenci veya kişi adı',
                  ),
                ),
                TextField(
                  controller: studentClass,
                  onChanged: (value) => refresh(() {
                    studentId = null;
                    memberId = null;
                    if (!dueManuallySet)
                      due = DateTime.now().add(
                        Duration(days: loanSettings.durationFor(value)),
                      );
                  }),
                  decoration: const InputDecoration(
                    labelText: 'Sınıf (isteğe bağlı)',
                  ),
                ),
                if (copies.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: copyChoice,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Ödünç verilecek nüsha',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'auto',
                        child: Text('Otomatik seç'),
                      ),
                      if (untrackedAvailable > 0)
                        DropdownMenuItem(
                          value: 'untracked',
                          child: Text(
                            'Kimliksiz nüsha ($untrackedAvailable uygun)',
                          ),
                        ),
                      ...available.map(
                        (copy) => DropdownMenuItem(
                          value: 'id:${copy['id']}',
                          child: Text(
                            (copy['accessionCode'] as String).isEmpty
                                ? 'Nüsha ${copy['id']}'
                                : copy['accessionCode'],
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => refresh(() => copyChoice = value!),
                  ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime(2100),
                      initialDate: due,
                    );
                    if (picked != null)
                      refresh(() {
                        due = picked;
                        dueManuallySet = true;
                      });
                  },
                  child: Text('Son tarih: ${due.day}.${due.month}.${due.year}'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isNotEmpty) {
                  Navigator.pop(ctx, {
                    'id': DateTime.now().microsecondsSinceEpoch.toString(),
                    'name': name.text.trim(),
                    'studentClass': studentClass.text.trim(),
                    if (studentId != null) 'studentId': studentId,
                    if (memberId != null) 'memberId': memberId,
                    'identitySource': memberId != null
                        ? 'member'
                        : studentId == null
                        ? 'manual'
                        : 'student',
                    'due': due.toIso8601String(),
                  });
                }
              },
              child: const Text('Ödünç ver'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      final violation = loanPolicyViolation(
        books,
        result,
        loanSettings,
        memberKind: members
            .where(
              (m) =>
                  m.id.toUpperCase() ==
                  (result['memberId'] ?? '').toString().toUpperCase(),
            )
            .firstOrNull
            ?.kind,
      );
      if (violation != null) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(violation)));
        return;
      }
      final duplicate = hasDuplicateBorrower(book, result);
      if (duplicate && (!await confirmDuplicateLoan(book, result) || !mounted))
        return;
      await save(
        books
            .map(
              (b) => b['id'] == book['id']
                  ? addLoan(
                      b,
                      result,
                      copyId: copyChoice.startsWith('id:')
                          ? copyChoice.substring(3)
                          : null,
                      untracked: copyChoice == 'untracked',
                      allowDuplicate: duplicate,
                    )
                  : b,
            )
            .toList(),
      );
    }
    name.dispose();
    studentClass.dispose();
  }

  Future<void> showLoans(Map<String, dynamic> book) async {
    if (saving) return;
    final loans = activeLoans(book);
    String? returnedCondition;
    bool? readingCompleted;
    String copyLabel(Map<String, dynamic> loan) {
      final id = loan['copyId'];
      if (id is! String) return '';
      final copies = ((book['copies'] as List?) ?? []).whereType<Map>().where(
        (c) =>
            c['id'] is String &&
            (c['id'] as String).toUpperCase() == id.toUpperCase(),
      );
      if (copies.isEmpty) return '';
      final code = (copies.first['accessionCode'] ?? '').toString();
      return 'Nüsha: ${code.isEmpty ? id : code} · ';
    }

    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('İade alınacak nüshayı seç'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: returnedCondition,
                  hint: const Text('Belirtilmedi'),
                  decoration: const InputDecoration(
                    labelText: 'İade edilen kitabın durumu',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Belirtilmedi'),
                    ),
                    ...[
                      'Yeni',
                      'İyi',
                      'Yıpranmış',
                      'Onarım gerekli',
                    ].map((s) => DropdownMenuItem(value: s, child: Text(s))),
                  ],
                  onChanged: (v) => refresh(() => returnedCondition = v),
                ),
                DropdownButtonFormField<bool>(
                  initialValue: readingCompleted,
                  hint: const Text('Belirtilmedi'),
                  decoration: const InputDecoration(
                    labelText: 'Kitap okundu mu?',
                  ),
                  items: const [
                    DropdownMenuItem<bool>(
                      value: null,
                      child: Text('Belirtilmedi'),
                    ),
                    DropdownMenuItem(value: true, child: Text('Evet')),
                    DropdownMenuItem(value: false, child: Text('Hayır')),
                  ],
                  onChanged: (v) => refresh(() => readingCompleted = v),
                ),
                ...loans
                    .map(
                      (l) => ListTile(
                        title: Text(
                          '${l['name']}${(l['studentClass'] ?? '').toString().isEmpty ? '' : ' · ${l['studentClass']}'}',
                        ),
                        subtitle: Text(
                          '${copyLabel(l)}${l['due'] == null ? 'Tarih kaydedilmemiş' : 'Son tarih: ${l['due'].toString().substring(0, 10)}'}',
                        ),
                        trailing: const Icon(Icons.assignment_return),
                        onTap: () => Navigator.pop(ctx, l['id'] as String),
                      ),
                    )
                    .toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
          ],
        ),
      ),
    );
    if (id != null) {
      try {
        await save(
          books
              .map(
                (b) => b['id'] == book['id']
                    ? returnLoan(
                        b,
                        id,
                        returnedCondition: returnedCondition,
                        readingCompleted: readingCompleted,
                      )
                    : b,
              )
              .toList(),
        );
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'İade kaydedilemedi; nüşa bilgilerini kontrol edin.',
              ),
            ),
          );
      }
    }
  }

  Future<void> extend(Map<String, dynamic> book) async {
    if (saving) return;
    final loans = activeLoans(book);
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Süresi uzatılacak ödünç'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: loans
                .map(
                  (l) => ListTile(
                    title: Text(
                      '${l['name']}${(l['studentClass'] ?? '').toString().isEmpty ? '' : ' · ${l['studentClass']}'}',
                    ),
                    subtitle: Text(
                      l['due'] == null
                          ? 'Tarih yok'
                          : 'Son tarih: ${l['due'].toString().split('T').first}',
                    ),
                    onTap: () => Navigator.pop(ctx, l['id'] as String),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    final record = loans.firstWhere((l) => l['id'] == id);
    final previous = DateTime.tryParse(record['due']?.toString() ?? '');
    final now = DateTime.now();
    final tomorrow = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    final next = previous == null
        ? tomorrow
        : DateTime(
            previous.year,
            previous.month,
            previous.day,
          ).add(const Duration(days: 1));
    final first = next.isAfter(tomorrow) ? next : tomorrow;
    final selected = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: DateTime(first.year + 10),
      initialDate: first,
    );
    if (selected != null && mounted) {
      await save(
        books
            .map((b) => b['id'] == book['id'] ? extendLoan(b, id, selected) : b)
            .toList(),
      );
    }
  }

  Future<void> markLost(Map<String, dynamic> book) async {
    if (saving) return;
    final loans = activeLoans(book);
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kayıp bildirilecek ödünç'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: loans
                .map(
                  (loan) => ListTile(
                    title: Text(loan['name']),
                    subtitle: Text((loan['studentClass'] ?? '').toString()),
                    onTap: () => Navigator.pop(ctx, loan['id'] as String),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaybı bildir'),
        content: const Text(
          'Ödünç kapatılacak ve kayıp nüsha ödünç verilebilir sayıdan çıkarılacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kayıp bildir'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await save(
        books
            .map((b) => b['id'] == book['id'] ? reportLost(b, id) : b)
            .toList(),
      );
    }
  }

  Future<void> resolveLoanIdentity(Map<String, dynamic> book) async {
    if (saving) return;
    final loans = activeLoans(
      book,
    ).where((l) => l['memberId'] == null).toList();
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce öğrenci kaydı ekleyin.')),
      );
      return;
    }
    final selectedLoan = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Kimliği düzeltilecek ödünç'),
        children: loans
            .map(
              (l) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, l),
                child: Text(
                  '${l['name']} · ${l['studentClass'] ?? ''}${l['needsIdentityReview'] == true ? ' · İncelenecek' : ''}',
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selectedLoan == null || !mounted) return;
    final selectedStudent = await showDialog<Student>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Doğru öğrenciyi seç'),
        children: students
            .map(
              (s) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, s),
                child: Text(
                  '${s.name} · ${s.number} · ${s.graduatedAt == null ? s.className : 'Mezun'}',
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selectedStudent == null || !mounted) return;
    final newClass = selectedStudent.graduatedAt == null
        ? selectedStudent.className
        : 'Mezun';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Öğrenci kimliğini düzelt'),
        content: Text(
          '${selectedLoan['name']} · ${selectedLoan['studentClass'] ?? ''} → ${selectedStudent.name} · $newClass\nDeğişiklik ödünç geçmişine kaydedilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Düzelt'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await save(
      books
          .map(
            (b) => b['id'] == book['id']
                ? assignStudentIdentity(
                    b,
                    selectedLoan['id'] as String,
                    studentId: selectedStudent.id,
                    name: selectedStudent.name,
                    studentClass: newClass,
                  )
                : b,
          )
          .toList(),
    );
  }

  Future<void> showCopies(Map<String, dynamic> book) async {
    while (mounted) {
      final current = books.firstWhere((b) => b['id'] == book['id']);
      final copies = ((current['copies'] as List?) ?? [])
          .cast<Map<String, dynamic>>();
      final loans = activeLoans(current);
      final action = await showDialog<Object>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fiziksel nüshalar'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: copies.map((copy) {
                final linked = loans
                    .where(
                      (l) =>
                          l['copyId'] is String &&
                          (l['copyId'] as String).toUpperCase() ==
                              (copy['id'] as String).toUpperCase(),
                    )
                    .toList();
                final place = [
                  copy['cabinet'],
                  copy['shelf'],
                ].where((v) => v is String && v.isNotEmpty).join(' · ');
                return ListTile(
                  onTap: () => Navigator.pop(ctx, copy),
                  title: Text(
                    (copy['accessionCode'] as String).isEmpty
                        ? 'Nüsha ${copy['id']}'
                        : copy['accessionCode'],
                  ),
                  subtitle: Text(
                    '${copy['condition']} · ${copy['status']}${linked.isEmpty ? '' : ' · Ödünç: ${linked.single['name']}'}${place.isEmpty ? '' : ' · $place'}${(copy['note'] as String).isEmpty ? '' : ' · ${copy['note']}'}',
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'add'),
              child: const Text('Nüsha ekle'),
            ),
          ],
        ),
      );
      if (action == null || !mounted) return;
      final original = action is Map ? Map<String, dynamic>.from(action) : null;
      var code = (original?['accessionCode'] ?? '').toString();
      var condition = (original?['condition'] ?? 'İyi').toString();
      var status = (original?['status'] ?? 'Rafta').toString();
      var cabinet = (original?['cabinet'] ?? '').toString();
      var shelf = (original?['shelf'] ?? '').toString();
      var note = (original?['note'] ?? '').toString();
      final loaned =
          original != null &&
          loans.any(
            (l) =>
                l['copyId'] is String &&
                (l['copyId'] as String).toUpperCase() ==
                    (original['id'] as String).toUpperCase(),
          );
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, refresh) {
            final conditions = [
              'Yeni',
              'İyi',
              'Yıpranmış',
              'Onarım gerekli',
              if (![
                'Yeni',
                'İyi',
                'Yıpranmış',
                'Onarım gerekli',
              ].contains(condition))
                condition,
            ];
            return AlertDialog(
              title: Text(original == null ? 'Nüsha ekle' : 'Nüshayı düzenle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: code,
                      onChanged: (v) => code = v,
                      decoration: const InputDecoration(
                        labelText: 'Demirbaş kodu',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: condition,
                      decoration: const InputDecoration(
                        labelText: 'Fiziksel durum',
                      ),
                      items: conditions
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (v) => refresh(() => condition = v!),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(
                        labelText: 'Nüsha durumu',
                      ),
                      items: ['Rafta', 'Onarımda', 'Kayıp', 'Düşüldü']
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: loaned
                          ? null
                          : (v) => refresh(() => status = v!),
                    ),
                    if (loaned)
                      const Text(
                        'Ödünçteki nüshanın durumu iade veya kayıp bildiriminden değiştirilir.',
                      ),
                    TextFormField(
                      initialValue: cabinet,
                      onChanged: (v) => cabinet = v,
                      decoration: const InputDecoration(labelText: 'Dolap'),
                    ),
                    TextFormField(
                      initialValue: shelf,
                      onChanged: (v) => shelf = v,
                      decoration: const InputDecoration(labelText: 'Raf'),
                    ),
                    TextFormField(
                      initialValue: note,
                      onChanged: (v) => note = v,
                      decoration: const InputDecoration(labelText: 'Not'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, {
                    ...?original,
                    'id':
                        original?['id'] ??
                        'copy-${DateTime.now().microsecondsSinceEpoch}',
                    'bookID': current['id'],
                    'accessionCode': code.trim(),
                    'condition': condition,
                    'status': status,
                    'note': note.trim(),
                    'addedAt':
                        original?['addedAt'] ??
                        DateTime.now().toIso8601String(),
                    'cabinet': cabinet.trim().isEmpty ? null : cabinet.trim(),
                    'shelf': shelf.trim().isEmpty ? null : shelf.trim(),
                  }),
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        ),
      );
      if (data == null || !mounted) continue;
      final duplicate =
          (data['accessionCode'] as String).isNotEmpty &&
          copies.any(
            (c) =>
                c['id'] != data['id'] &&
                (c['accessionCode'] as String).toLowerCase() ==
                    (data['accessionCode'] as String).toLowerCase(),
          );
      if (duplicate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu demirbaş kodu zaten kullanılıyor.')),
        );
        continue;
      }
      try {
        final updated = original == null
            ? addPhysicalCopy(current, data)
            : editPhysicalCopy(current, data);
        await save(
          books.map((b) => b['id'] == current['id'] ? updated : b).toList(),
        );
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Nüsha kaydedilemedi.')));
      }
    }
  }

  Future<void> showReservations(Map<String, dynamic> book) async {
    final before = books.firstWhere((b) => b['id'] == book['id']);
    final refreshed = advanceReservationQueue(before);
    if (jsonEncode(reservationsOf(before)) !=
        jsonEncode(reservationsOf(refreshed))) {
      await save(
        books.map((b) => b['id'] == before['id'] ? refreshed : b).toList(),
      );
    }
    while (mounted) {
      final current = books.firstWhere((b) => b['id'] == book['id']);
      final active = reservationsOf(current).where(isActiveReservation).toList()
        ..sort(
          (a, b) =>
              (a['createdAt'] as String).compareTo(b['createdAt'] as String),
        );
      final choice = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rezervasyon sırası'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (active.isEmpty) const Text('Bekleyen rezervasyon yok.'),
                  ...active.map(
                    (r) => ListTile(
                      title: Text('${r['name']} · ${r['studentClass']}'),
                      subtitle: Text(
                        isReadyReservation(r)
                            ? 'Teslim için hazır'
                            : r['notifiedAt'] == null
                            ? 'Sırada'
                            : 'Süresi doldu',
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Rezervasyon işlemleri',
                        onSelected: (action) => Navigator.pop(ctx, {
                          'action': action,
                          'reservation': r,
                        }),
                        itemBuilder: (_) => [
                          if (isReadyReservation(r))
                            const PopupMenuItem(
                              value: 'deliver',
                              child: Text('Ödünç ver'),
                            ),
                          const PopupMenuItem(
                            value: 'cancel',
                            child: Text('Rezervasyonu iptal et'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, {'action': 'notifications'}),
              child: const Text('Bildirimler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {'action': 'add'}),
              child: const Text('Sıraya ekle'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      final action = choice['action'];
      final selected = choice['reservation'] as Map<String, dynamic>?;
      if (action == 'notifications') {
        try {
          final allowed = await ReservationNotifications().request();
          if (!mounted) return;
          if (allowed) {
            await ReservationNotifications().synchronize(
              [],
              books,
              force: true,
            );
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Hazır rezervasyon bildirimleri açık.'),
                ),
              );
          } else {
            final settings = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Bildirim izni kapalı'),
                content: const Text(
                  'Hazır rezervasyonları uygulamada görebilirsiniz. Bildirim almak için Android ayarlarından izin verebilirsiniz.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Kapat'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Ayarları aç'),
                  ),
                ],
              ),
            );
            if (settings == true)
              await ReservationNotifications.channel.invokeMethod<bool>(
                'settings',
              );
          }
        } catch (_) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bildirim ayarları açılamadı.')),
            );
        }
      } else if (action == 'add') {
        var name = '', studentClass = '';
        Student? student;
        Member? member;
        final entry = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, refresh) => AlertDialog(
              title: const Text('Rezervasyon ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (students.any((s) => s.graduatedAt == null))
                      TextButton(
                        onPressed: () async {
                          final chosen = await showDialog<Student>(
                            context: ctx,
                            builder: (c) => SimpleDialog(
                              title: const Text('Öğrenci seç'),
                              children: students
                                  .where((s) => s.graduatedAt == null)
                                  .map(
                                    (s) => SimpleDialogOption(
                                      onPressed: () => Navigator.pop(c, s),
                                      child: Text(
                                        '${s.name} · ${s.className} · ${s.number}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          );
                          if (chosen != null)
                            refresh(() {
                              student = chosen;
                              member = null;
                              name = chosen.name;
                              studentClass = chosen.className;
                            });
                        },
                        child: Text(
                          student == null
                              ? 'Kayıtlı öğrenci seç'
                              : 'Seçilen: ${student!.name} · ${student!.className}',
                        ),
                      ),
                    if (members.isNotEmpty)
                      TextButton(
                        onPressed: () async {
                          final chosen = await showDialog<Member>(
                            context: ctx,
                            builder: (dialog) => SimpleDialog(
                              title: const Text('Üye seç'),
                              children: members
                                  .map(
                                    (m) => SimpleDialogOption(
                                      onPressed: () => Navigator.pop(dialog, m),
                                      child: Text(
                                        '${m.name} · ${m.kindTitle} · ${m.number}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          );
                          if (chosen != null)
                            refresh(() {
                              member = chosen;
                              student = null;
                              name = chosen.name;
                              studentClass = '';
                            });
                        },
                        child: Text(
                          member == null
                              ? 'Kayıtlı üye seç'
                              : 'Seçilen: ${member!.name} · ${member!.kindTitle}',
                        ),
                      ),
                    if (student == null && member == null) ...[
                      TextField(
                        onChanged: (v) => name = v,
                        decoration: const InputDecoration(
                          labelText: 'Kişi adı',
                        ),
                      ),
                      TextField(
                        onChanged: (v) => studentClass = v,
                        decoration: const InputDecoration(labelText: 'Sınıf'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () {
                    if (name.trim().isNotEmpty)
                      Navigator.pop(ctx, {
                        'id':
                            'reservation-${DateTime.now().microsecondsSinceEpoch}',
                        'name': name.trim(),
                        'studentClass': studentClass.trim(),
                        if (student != null) 'studentId': student!.id,
                        if (member != null) 'memberId': member!.id,
                        'createdAt': DateTime.now().toIso8601String(),
                        'isClosed': false,
                      });
                  },
                  child: const Text('Ekle'),
                ),
              ],
            ),
          ),
        );
        if (entry == null || !mounted) continue;
        try {
          final next = advanceReservationQueue(addReservation(current, entry));
          await save(
            books.map((b) => b['id'] == current['id'] ? next : b).toList(),
          );
        } catch (_) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Rezervasyon eklenemedi; öğrenci zaten sırada olabilir.',
                ),
              ),
            );
        }
      } else if (selected != null && action == 'cancel') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Rezervasyon iptal edilsin mi?'),
            content: Text('${selected['name']}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('İptal et'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) continue;
        final next = advanceReservationQueue(
          closeReservation(current, selected['id'] as String, 'cancelled'),
        );
        await save(
          books.map((b) => b['id'] == current['id'] ? next : b).toList(),
        );
      } else if (selected != null && action == 'deliver') {
        final member = members
            .where(
              (m) =>
                  m.id.toUpperCase() ==
                  (selected['memberId'] ?? '').toString().toUpperCase(),
            )
            .firstOrNull;
        final violation = loanPolicyViolation(
          books,
          selected,
          loanSettings,
          memberKind: member?.kind,
        );
        if (violation != null) {
          if (mounted)
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(violation)));
          continue;
        }
        final duplicate = hasDuplicateBorrower(current, selected);
        if (duplicate &&
            (!await confirmDuplicateLoan(current, selected) || !mounted))
          continue;
        final due = await showDatePicker(
          context: context,
          initialDate: DateTime.now().add(
            Duration(
              days: member == null
                  ? loanSettings.durationFor(
                      (selected['studentClass'] ?? '').toString(),
                    )
                  : loanSettings.memberRuleFor(member.kind)?.days ??
                        loanSettings.days,
            ),
          ),
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime(2100),
        );
        if (due == null || !mounted) continue;
        try {
          final next = lendReservation(
            current,
            selected['id'] as String,
            loanId: DateTime.now().microsecondsSinceEpoch.toString(),
            due: due,
            allowDuplicate: duplicate,
          );
          await save(
            books.map((b) => b['id'] == current['id'] ? next : b).toList(),
          );
        } catch (_) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Rezervasyon ödünç verilemedi.')),
            );
        }
      }
    }
  }

  Future<void> showHistory(Map<String, dynamic> book) async {
    final events = loanHistory(book).reversed.toList();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ödünç geçmişi'),
        content: SizedBox(
          width: double.maxFinite,
          child: events.isEmpty
              ? const Text(
                  'Henüz geçmiş kaydı yok. Önceki sürümdeki hareketler geriye dönük oluşturulmaz.',
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: events.length,
                  itemBuilder: (ctx, i) {
                    final event = events[i];
                    final date = DateTime.tryParse(
                      event['date']?.toString() ?? '',
                    );
                    final day = date == null
                        ? ''
                        : '${date.day}.${date.month}.${date.year}';
                    return ListTile(
                      title: Text('${event['person']}'),
                      subtitle: Text(
                        '${loanEventLabel(event['kind'] as String?)} • $day${event['late'] == true ? ' • Gecikmiş' : ''}${event['returnedCondition'] == null ? '' : ' • ${event['returnedCondition']}'}${event['readingCompleted'] == null
                            ? ''
                            : event['readingCompleted'] == true
                            ? ' • Okundu'
                            : ' • Okunmadı'}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Future<void> trashBook(Map<String, dynamic> book) async {
    if (saving) return;
    if (activeLoans(book).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce ödünçteki nüshaları iade alın.')),
      );
      return;
    }
    if (reservationsOf(book).any(isActiveReservation)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce açık rezervasyonları kapatın.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çöp kutusuna taşı'),
        content: Text(
          '“${book['title']}” çöp kutusuna taşınacak. Sonra geri yükleyebilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Taşı'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await save(
        books.map((b) => b['id'] == book['id'] ? moveToTrash(b) : b).toList(),
      );
    }
  }

  Future<void> changeWithdrawal(Map<String, dynamic> book) async {
    if (saving) return;
    if (book['isWithdrawn'] == true) {
      final restored = {
        ...book,
        'isWithdrawn': false,
        'withdrawnReason': null,
        'withdrawnDate': null,
      };
      await save(
        books
            .map(
              (b) =>
                  b['id'] == book['id'] ? advanceReservationQueue(restored) : b,
            )
            .toList(),
      );
      return;
    }
    if (activeLoans(book).isNotEmpty ||
        reservationsOf(book).any(isActiveReservation)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Önce etkin ödünçleri ve açık rezervasyonları kapatın.',
          ),
        ),
      );
      return;
    }
    var reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Koleksiyondan düş'),
        content: TextField(
          onChanged: (value) => reason = value,
          decoration: const InputDecoration(labelText: 'Düşülme nedeni'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Düş'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await save(
        books
            .map(
              (b) => b['id'] == book['id']
                  ? {
                      ...b,
                      'isWithdrawn': true,
                      'withdrawnReason': reason.trim(),
                      'withdrawnDate': DateTime.now().toIso8601String(),
                    }
                  : b,
            )
            .toList(),
      );
    }
  }

  Future<void> showTrash() async {
    if (saving) return;
    final deleted = books.where((b) => b['deletedAt'] != null).toList();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çöp kutusu'),
        content: SizedBox(
          width: double.maxFinite,
          child: deleted.isEmpty
              ? const Text('Çöp kutusu boş.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: deleted.length,
                  itemBuilder: (ctx, i) {
                    final book = deleted[i];
                    return ListTile(
                      title: Text(book['title']),
                      subtitle: Text(book['author']),
                      trailing: const Icon(Icons.restore),
                      onTap: () => Navigator.pop(ctx, book['id'] as String),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
    if (id != null) {
      await save(books.map((b) => b['id'] == id ? restoreBook(b) : b).toList());
    }
  }

  Future<void> exportCatalogPdf() async {
    if (loading || saving || error != null) return;
    final active = books.where((book) => book['deletedAt'] == null).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Katalog PDF kaydet'),
        content: Text(
          '${active.length} kitap için ad, yazar, yayınevi, ISBN, kategori, konum ve nüsha bilgilerini içeren PDF oluşturulacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dosya seç'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => saving = true);
    try {
      final rows = active
          .map(
            (book) => {
              'title': book['title'],
              'author': book['author'],
              'publisher': book['publisher'] ?? '',
              'isbn': book['isbn'],
              'category': book['category'] ?? '',
              'shelf': book['shelf'],
              'quantity': book['quantity'],
              'available': availableCopies(book),
            },
          )
          .toList();
      final saved = await const MethodChannel(
        'kitapbul/files',
      ).invokeMethod<bool>('exportPdf', {'data': jsonEncode(rows)});
      if (saved == true && mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Katalog PDF dosyası kaydedildi.')),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF dosyası kaydedilemedi.')),
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> exportCatalogCsv() async {
    if (loading || saving || error != null) return;
    final selected = <CatalogColumn>{
      CatalogColumn.title,
      CatalogColumn.author,
      CatalogColumn.publisher,
      CatalogColumn.isbn,
      CatalogColumn.category,
      CatalogColumn.quantity,
      CatalogColumn.shelf,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('Kataloğu CSV olarak kaydet'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Çöp kutusundakiler hariç tüm katalog aktarılır. Kaydedilecek sütunları seçin.',
                  ),
                  ...CatalogColumn.values.map(
                    (column) => CheckboxListTile(
                      title: Text(column.label),
                      value: selected.contains(column),
                      onChanged: (checked) => refresh(() {
                        if (checked == true) {
                          selected.add(column);
                        } else {
                          selected.remove(column);
                        }
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Dosya seç'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => saving = true);
    try {
      final data = catalogCsv(
        books,
        CatalogColumn.values.where(selected.contains).toList(),
      );
      final saved = await const MethodChannel(
        'kitapbul/files',
      ).invokeMethod<bool>('exportCsv', {'data': data});
      if (saved == true && mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Katalog CSV dosyası kaydedildi.')),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV dosyası kaydedilemedi.')),
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> exportCatalogXlsx([List<Map<String, dynamic>>? subset]) async {
    if (saving || loading || error != null) return;
    final target = subset ?? books;
    if (target.where((b) => b['deletedAt'] == null).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışa aktarılacak kitap kaydı yok.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      final bytes = buildCatalogXlsx(target);
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final saved = await const MethodChannel('kitapbul/files')
          .invokeMethod<bool>('exportXlsx', {
            'bytes': bytes,
            'filename': 'KitapListesi_$stamp.xlsx',
          });
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Excel (.xlsx) kitap listesi kaydedildi.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel dosyası kaydedilemedi.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> importCatalogXlsx() async {
    if (saving || loading || error != null) return;
    setState(() => saving = true);
    try {
      final bytes = await const MethodChannel(
        'kitapbul/files',
      ).invokeMethod<Uint8List>('pickXlsx');
      if (bytes == null || !mounted) return;
      final incoming = parseCatalogXlsx(bytes);
      if (!mounted) return;

      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excel kitap listesi içe aktarılsın mı?'),
          content: Text(
            'Excel tablosundan ${incoming.length} kitap satırı okundu.\n\n'
            'Aynı ISBN\'e sahip uyumlu kayıtların nüsha sayısı artırılır, yeni kitaplar kataloğa eklenir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('İçe Aktar'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;

      final next = [...books];
      var added = 0;
      var merged = 0;
      for (final item in incoming) {
        final isbnKey = canonicalIsbn('${item['isbn'] ?? ''}');
        var mergeIdx = -1;
        if (isbnKey != null) {
          mergeIdx = next.indexWhere(
            (b) =>
                b['deletedAt'] == null &&
                canonicalIsbn('${b['isbn'] ?? ''}') == isbnKey &&
                canMergeCopies(item, b),
          );
        }
        if (mergeIdx >= 0) {
          next[mergeIdx] = normalizeBook(mergeCopies(item, next[mergeIdx]));
          merged++;
        } else {
          next.add(normalizeBook(item));
          added++;
        }
      }

      final previous = books;
      final store = CatalogStore(await getApplicationDocumentsDirectory());
      await store.save(next);
      if (mounted) setState(() => books = next);
      await syncReservationNotifications(previous, next);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Excel içe aktarıldı: $added yeni kitap eklendi, $merged mevcut kayda nüsha eklendi.',
            ),
          ),
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Excel dosyası okunamadı. Geçerli bir .xlsx seçin.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> openBookCoverLightbox(
    Map<String, dynamic> book,
    String heroTag,
  ) async {
    await showBookCoverLightbox(
      context,
      book,
      heroTag: heroTag,
      onDownloadCover: () async {
        if (!mounted || saving) return null;
        try {
          final downloaded = await fetchBestCoverForBook(book);
          if (downloaded == null || !mounted) return null;
          final updatedList = withDownloadedCover(
            books,
            book['id'] as String,
            '${book['isbn'] ?? ''}',
            downloaded.bytes,
            source: downloaded.source,
            allowTitleLookup: true,
          );
          if (updatedList == null) return null;
          await save(updatedList);
          return books.where((b) => b['id'] == book['id']).firstOrNull;
        } catch (_) {
          return null;
        }
      },
    );
  }

  Future<void> openClassLoan() async {
    if (saving || loading || error != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClassLoanPage(
          books: books,
          students: students,
          settings: loanSettings,
          save: (updated) async {
            try {
              final previous = books;
              await CatalogStore(
                await getApplicationDocumentsDirectory(),
              ).save(updated);
              if (mounted) setState(() => books = updated);
              await syncReservationNotifications(previous, updated);
              return true;
            } catch (_) {
              return false;
            }
          },
        ),
      ),
    );
  }

  Future<void> openTextbooks() async {
    if (saving || loading || error != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextbookPage(
          books: books,
          students: students,
          save: (updated) async {
            try {
              final previous = books;
              await CatalogStore(
                await getApplicationDocumentsDirectory(),
              ).save(updated);
              if (mounted) setState(() => books = updated);
              await syncReservationNotifications(previous, updated);
              return true;
            } catch (_) {
              return false;
            }
          },
        ),
      ),
    );
  }

  Future<void> openDataQuality() async {
    if (saving || loading || error != null) return;
    final selected = await Navigator.of(context).push<DataQualityField>(
      MaterialPageRoute(
        builder: (_) => DataQualityPage(
          books: books,
          allowTitleCoverLookup: true,
          applyCover: (id, isbn, bytes, source) async {
            if (!mounted || saving) return false;
            final updated = withDownloadedCover(
              books,
              id,
              isbn,
              bytes,
              source: source,
              allowTitleLookup: true,
            );
            if (updated == null) return false;
            setState(() => saving = true);
            try {
              final store = CatalogStore(
                await getApplicationDocumentsDirectory(),
              );
              final current = await store.load();
              if (jsonEncode(current) !=
                  jsonEncode(books.map(normalizeBook).toList())) {
                return false;
              }
              await store.save(updated);
              if (mounted) setState(() => books = updated);
              return true;
            } catch (_) {
              return false;
            } finally {
              if (mounted) setState(() => saving = false);
            }
          },
          applyMetadata: (id, info, coverBytes) async {
            if (!mounted || saving) return false;
            final index = books.indexWhere((b) => b['id'] == id);
            if (index < 0 || !isQualityCandidate(books[index])) {
              return false;
            }
            final target = Map<String, dynamic>.from(books[index]);
            var changed = false;

            if (missingQualityField(target, DataQualityField.author) &&
                (info['author'] ?? '').trim().isNotEmpty) {
              target['author'] = info['author']!.trim();
              changed = true;
            }
            if (missingQualityField(target, DataQualityField.isbn)) {
              final incomingIsbn = (info['isbn'] ?? '').trim();
              if (incomingIsbn.isNotEmpty && isValidIsbn(incomingIsbn)) {
                target['isbn'] = cleanIsbnInput(incomingIsbn);
                changed = true;
              }
            }
            for (final (fieldKey, infoKey) in const [
              ('publisher', 'publisher'),
              ('category', 'category'),
              ('pageCount', 'pageCount'),
              ('publicationYear', 'publicationYear'),
              ('language', 'language'),
              ('edition', 'edition'),
              ('readingLevel', 'readingLevel'),
            ]) {
              if ((target[fieldKey] ?? '').toString().trim().isEmpty &&
                  (info[infoKey] ?? '').trim().isNotEmpty) {
                target[fieldKey] = info[infoKey]!.trim();
                changed = true;
              }
            }
            if (coverBytes != null &&
                missingQualityField(target, DataQualityField.cover) &&
                !coverFieldLocked(target)) {
              target['coverBase64'] = storeCoverBytes(coverBytes);
              final srcRaw = info['source'] ?? '';
              if (srcRaw.contains('Kitapyurdu')) {
                target['coverSource'] = 'Kitapyurdu';
              } else if (srcRaw.contains('Amazon')) {
                target['coverSource'] = 'Amazon';
              }
              changed = true;
            }
            if (!changed) return false;

            setState(() => saving = true);
            try {
              final normalizedTarget = normalizeBook(target);
              final updated = [
                for (var i = 0; i < books.length; i++)
                  if (i == index) normalizedTarget else books[i],
              ];
              final store = CatalogStore(
                await getApplicationDocumentsDirectory(),
              );
              final current = await store.load();
              if (jsonEncode(current) !=
                  jsonEncode(books.map(normalizeBook).toList())) {
                return false;
              }
              await store.save(updated);
              if (mounted) setState(() => books = updated);
              return true;
            } catch (_) {
              return false;
            } finally {
              if (mounted) setState(() => saving = false);
            }
          },
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        qualityFilter = selected;
        showWithdrawn = false;
        selectedCategory = null;
        query = '';
        searchController.clear();
      });
    }
  }

  Future<bool> saveShelfInventorySession(InventorySession next) async {
    try {
      final store = CatalogStore(await getApplicationDocumentsDirectory());
      await store.save(books, inventorySession: next);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> openVoiceAssistant() async {
    if (loading || error != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceLibraryAssistantPage(
          initialBooks: books,
          students: students,
          dutyRoster: dutyRoster,
          onSaveBooks: save,
        ),
      ),
    );
  }

  Future<void> openBulkIsbnImporter() async {
    if (loading || saving || error != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BulkIsbnImporterPage(
          initialBooks: books,
          onSaveBooks: save,
        ),
      ),
    );
  }

  Future<void> openFourPageVision() async {
    if (loading || saving || error != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FourPageBookScannerPage(
          initialBooks: books,
          onSaveBooks: save,
        ),
      ),
    );
  }

  Future<void> openShelfPhotoScanner() async {
    if (loading || saving || error != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShelfPhotoScannerPage(
          initialBooks: books,
          onSaveBooks: save,
          onSaveInventorySession: saveShelfInventorySession,
        ),
      ),
    );
  }

  Future<void> showQuickRegister() async {
    if (loading || saving || error != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuickRegisterPage(
          initialBooks: books,
          saveBooks: (updated) async {
            if (!mounted || saving) return false;
            final previous = books;
            setState(() => saving = true);
            try {
              final store = CatalogStore(
                await getApplicationDocumentsDirectory(),
              );
              final current = await store.load();
              if (jsonEncode(current) !=
                  jsonEncode(books.map(normalizeBook).toList())) {
                return false;
              }
              final normalized = updated.map(normalizeBook).toList();
              await store.save(normalized);
              if (mounted) setState(() => books = normalized);
              await syncReservationNotifications(previous, normalized);
              return true;
            } catch (_) {
              return false;
            } finally {
              if (mounted) setState(() => saving = false);
            }
          },
          onEditBook: (book) async {
            final latest = books
                .where((b) => b['id'] == book['id'])
                .firstOrNull;
            await add(latest ?? book);
            return books;
          },
        ),
      ),
    );
  }

  Future<void> searchKitapyurduAndRegister() async {
    if (loading || saving || error != null) return;
    final picked = await showDialog<FetchedBookData>(
      context: context,
      builder: (_) => const KitapyurduSearchDialog(),
    );
    if (picked == null || !mounted) return;
    final meta = picked.metadata;
    final prefill = <String, dynamic>{
      if ((meta['title'] ?? '').trim().isNotEmpty)
        'title': meta['title']!.trim(),
      if ((meta['author'] ?? '').trim().isNotEmpty)
        'author': meta['author']!.trim(),
      if ((meta['isbn'] ?? '').trim().isNotEmpty &&
          isValidIsbn(meta['isbn']!))
        'isbn': cleanIsbnInput(meta['isbn']!),
      if ((meta['publisher'] ?? '').trim().isNotEmpty)
        'publisher': meta['publisher']!.trim(),
      if ((meta['category'] ?? '').trim().isNotEmpty)
        'category': meta['category']!.trim(),
      if ((meta['publicationYear'] ?? '').trim().isNotEmpty)
        'publicationYear': meta['publicationYear']!.trim(),
      if ((meta['pageCount'] ?? '').trim().isNotEmpty)
        'pageCount': meta['pageCount']!.trim(),
      if ((meta['edition'] ?? '').trim().isNotEmpty)
        'edition': meta['edition']!.trim(),
      if ((meta['language'] ?? '').trim().isNotEmpty)
        'language': meta['language']!.trim(),
      if (picked.coverBytes != null)
        'coverBase64': storeCoverBytes(picked.coverBytes!),
    };
    await add(null, prefill);
  }

  Future<void> showInventory() async {
    try {
      final store = CatalogStore(await getApplicationDocumentsDirectory());
      final initial = await store.loadInventory();
      final history = await store.loadInventoryHistory();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InventoryPage(
            books: books,
            currentBooks: () => books,
            initialSession: initial,
            initialHistory: history,
            archive: (session, previous, next) async {
              try {
                final stored = await store.load();
                final currentSession = await store.loadInventory();
                final currentHistory = await store.loadInventoryHistory();
                if (jsonEncode(stored) !=
                        jsonEncode(books.map(normalizeBook).toList()) ||
                    jsonEncode(currentSession?.toJson()) !=
                        jsonEncode(session.toJson()) ||
                    jsonEncode(
                          currentHistory.map((e) => e.toJson()).toList(),
                        ) !=
                        jsonEncode(previous.map((e) => e.toJson()).toList()))
                  return false;
                await store.save(
                  books,
                  clearInventorySession: true,
                  inventoryHistory: next,
                );
                return true;
              } catch (_) {
                return false;
              }
            },
            save: (previous, next) async {
              try {
                final stored = await store.load();
                final storedSession = await store.loadInventory();
                if (jsonEncode(stored) !=
                        jsonEncode(books.map(normalizeBook).toList()) ||
                    jsonEncode(storedSession?.toJson()) !=
                        jsonEncode(previous?.toJson()))
                  return false;
                await store.save(
                  books,
                  inventorySession: next,
                  clearInventorySession: next == null,
                );
                return true;
              } catch (_) {
                return false;
              }
            },
            registerUnknownBarcode:
                (currentSession, barcode, scannedCount) async {
                  if (!mounted || saving) return null;
                  final cleanCode = barcode.trim();
                  final isIsbnCode =
                      cleanCode.isNotEmpty && isValidIsbn(cleanCode);
                  final prefill = <String, dynamic>{
                    'shelf': currentSession.location ?? '',
                    'quantity': scannedCount > 0 ? scannedCount : 1,
                    if (isIsbnCode)
                      'isbn': cleanIsbnInput(cleanCode)
                    else
                      'accessionCode': cleanCode,
                  };
                  if (isIsbnCode) {
                    try {
                      final info = await lookupIsbn(cleanCode);
                      if (info != null) {
                        for (final k in [
                          'title',
                          'author',
                          'publisher',
                          'category',
                          'publicationYear',
                          'pageCount',
                          'edition',
                          'language',
                          'readingLevel',
                        ]) {
                          final v = (info[k] ?? '').trim();
                          if (v.isNotEmpty) prefill[k] = v;
                        }
                        Uint8List? coverBytes;
                        final coverUrl = (info['coverUrl'] ?? '').trim();
                        if (coverUrl.isNotEmpty) {
                          try {
                            coverBytes = await fetchCoverBytesFromUrl(coverUrl);
                          } catch (_) {}
                        }
                        if (coverBytes == null) {
                          try {
                            coverBytes =
                                (await fetchBestCover(cleanCode))?.bytes;
                          } catch (_) {}
                        }
                        if (coverBytes != null) {
                          prefill['coverBase64'] = storeCoverBytes(coverBytes);
                        }
                      }
                    } catch (_) {}
                  }
                  if (!mounted) return null;
                  var created = await add(null, prefill, false);
                  if (created == null || !mounted) return null;

                  final existingIdx = books.indexWhere(
                    (b) => b['id'] == created!['id'],
                  );
                  if (existingIdx < 0 &&
                      !isIsbnCode &&
                      (created['accessionCode'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty &&
                      created['copies'] == null) {
                    final bookId = created['id'] as String;
                    final shelfVal = (created['shelf'] as String? ?? '').trim();
                    created = {
                      ...created,
                      'copies': [
                        {
                          'id': '${bookId}_c1',
                          'bookID': bookId,
                          'accessionCode':
                              (created['accessionCode'] as String).trim(),
                          'condition': 'İyi',
                          'status': 'Rafta',
                          'note': '',
                          'addedAt': DateTime.now().toIso8601String(),
                          if (shelfVal.isNotEmpty) 'shelf': shelfVal,
                        },
                      ],
                    };
                  }

                  final normalizedBook = normalizeBook(created);
                  final nextBooks = existingIdx >= 0
                      ? [
                          for (var i = 0; i < books.length; i++)
                            if (i == existingIdx) normalizedBook else books[i],
                        ]
                      : [...books, normalizedBook];
                  final nextSession = integrateRegisteredBookIntoInventory(
                    currentSession,
                    normalizedBook,
                  );

                  setState(() => saving = true);
                  try {
                    final stored = await store.load();
                    final storedSession = await store.loadInventory();
                    if (jsonEncode(stored) !=
                            jsonEncode(books.map(normalizeBook).toList()) ||
                        jsonEncode(storedSession?.toJson()) !=
                            jsonEncode(currentSession.toJson())) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Katalog veya sayım başka yerde değişti; yeniden deneyin.',
                            ),
                          ),
                        );
                      }
                      return null;
                    }
                    await store.save(
                      nextBooks,
                      inventorySession: nextSession,
                    );
                    if (mounted) setState(() => books = nextBooks);
                    return nextSession;
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Kayıt ve sayım güncellenemedi.'),
                        ),
                      );
                    }
                    return null;
                  } finally {
                    if (mounted) setState(() => saving = false);
                  }
                },
          ),
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sayım kaydı açılamadı.')));
    }
  }

  Future<void> exportCatalog() async {
    if (saving || loading || error != null) return;
    setState(() => saving = true);
    File? zip;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final store = CatalogStore(docs);
      // Kapaklar `file:` referansı olarak kalır; görseller ZIP'e ayrı kayıt
      // olarak akışla yazılır; katalog JSON'u için ZIP sınırı (64 MB) geçerlidir.
      final catalogJson = encodeAndroidBackup(
        books,
        students: students,
        members: members,
        iphoneSupplement: await store.loadIPhoneSupplement(),
        includeInventory: true,
        inventorySession: await store.loadInventory(),
        inventoryHistory: await store.loadInventoryHistory(),
        maxBytes: maxZipCatalogBytes,
      );
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/zip-export');
      await dir.create(recursive: true);
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final outPath = '${dir.path}/kitap-bul-yedek-$stamp.zip';
      zip = File(outPath);
      final docsPath = docs.path;
      final summary = await _runZipWrite(catalogJson, docsPath, outPath);
      final saved = await const MethodChannel('kitapbul/files')
          .invokeMethod<bool>('exportZip', {
            'path': outPath,
            'filename': 'kitap-bul-yedek-$stamp.zip',
          });
      if (mounted && saved == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Yedek kaydedildi: ${summary.books} kitap, ${summary.images} görsel, ${summary.preservedFiles} saklanan iPhone dosyası.',
            ),
          ),
        );
      }
    } on FormatException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yedek kaydedilemedi. Tekrar deneyin.')),
        );
      }
    } finally {
      try {
        if (zip != null && await zip.exists()) await zip.delete();
      } catch (_) {}
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> importCatalog() async {
    if (saving || loading || error != null) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Yedeği geri yükle'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'zip'),
            child: const ListTile(
              leading: Icon(Icons.folder_zip_outlined),
              title: Text('ZIP yedeği (önerilen)'),
              subtitle: Text('Kapaklar ve iPhone tarama kayıtları dahil'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'json'),
            child: const ListTile(
              leading: Icon(Icons.data_object),
              title: Text('Eski JSON yedeği'),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'zip') await importZipCatalog();
    if (choice == 'json') await importJsonCatalog();
  }

  Future<void> importZipCatalog() async {
    if (saving || loading || error != null) return;
    setState(() => saving = true);
    String? path;
    try {
      path = await const MethodChannel(
        'kitapbul/files',
      ).invokeMethod<String>('importZip');
      if (path == null || !mounted) return;
      final zipPath = path;
      // Doğrulama turu: hiçbir şey yazılmaz.
      final verified = await _runZipVerify(zipPath);
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ZIP yedeğini geri yükle'),
          content: Text(
            'Bütünlük doğrulandı (${verified.createdAt}). ${verified.books.length} kitap, ${verified.imageRefs.length} görsel${verified.students == null ? '' : ', ${verified.students!.length} öğrenci'}${verified.members == null ? '' : ', ${verified.members!.length} üye'} ve ${verified.preserved.length} saklanan iPhone dosyası geri yüklenecek. Mevcut katalog önce doğrulanmış ayrı bir kopyaya alınır; cihazdaki görseller ve tarama kayıtları silinmez.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Geri yükle'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      final docs = await getApplicationDocumentsDirectory();
      final store = CatalogStore(docs);
      await store.snapshotBeforeIPhoneImport(label: 'pre-zip-restore');
      final docsPath = docs.path;
      await _runZipInstall(zipPath, docsPath, verified);
      // installZipBackupFiles her görselin gerçek depoda sağlam olduğunu
      // doğruladı; katalog bu referans kümesine karşı yeniden çözümlenir.
      final incoming = parseAndroidBackup(
        verified.catalogJson,
        availableImageRefs: verified.imageRefs,
      );
      await store.save(
        incoming,
        students: verified.students,
        members: verified.members,
        clearImportReceipt: true,
        inventorySession: verified.inventorySession,
        clearInventorySession: verified.inventorySession == null,
        inventoryHistory: verified.inventoryHistory,
        iphoneSupplement: verified.supplement,
        clearIPhoneSupplement: verified.supplement == null,
      );
      await syncReservationNotifications(books, incoming);
      if (mounted) {
        setState(() {
          books = incoming;
          if (verified.students != null) students = verified.students!;
          if (verified.members != null) members = verified.members!;
          loanSettings = verified.loanSettings;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ZIP yedeği geri yüklendi.')),
        );
      }
    } on FormatException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yedek reddedildi: ${e.message}')),
        );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yedek geri yüklenemedi; mevcut katalog korunuyor.'),
          ),
        );
      }
    } finally {
      try {
        if (path != null && await File(path).exists()) await File(path).delete();
      } catch (_) {}
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> importJsonCatalog() async {
    if (saving || loading || error != null) return;
    setState(() => saving = true);
    try {
      final data = await const MethodChannel(
        'kitapbul/files',
      ).invokeMethod<String>('import');
      if (data == null || !mounted) return;
      final incoming = parseAndroidBackup(data);
      final incomingStudents = parseBackupStudents(data);
      final incomingMembers = parseBackupMembers(data);
      final incomingInventory = parseBackupInventory(data);
      final incomingHistory = parseBackupInventoryHistory(data);
      final incomingSupplement = parseBackupIPhoneSupplement(data);
      final incomingSettings = incomingSupplement == null
          ? const LoanSettings()
          : LoanSettings.fromSupplement(incomingSupplement);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Yedeği geri yükle'),
          content: Text(
            '${incoming.length} kitap${incomingStudents == null ? '' : ', ${incomingStudents.length} öğrenci'}${incomingMembers == null ? '' : ', ${incomingMembers.length} üye'} içeren Android yedeği geri yüklenecek. Önceki kayıtlar yerel yedekte korunacak.${incomingStudents == null ? ' Bu eski yedek öğrencileri değiştirmez.' : ''}${incomingMembers == null ? ' Mevcut üyeler korunacak.' : ''}${incomingInventory.present ? ' Yedekteki sayım durumu da geri yüklenecek.' : ' Mevcut sayım korunacak; sayımın başlangıç kayıtları değişmez.'}${incomingHistory == null ? ' Sayım geçmişi korunacak.' : ' Sayım geçmişi de yedekten geri yüklenecek.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Geri yükle'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      final store = CatalogStore(await getApplicationDocumentsDirectory());
      await store.save(
        incoming,
        students: incomingStudents,
        members: incomingMembers,
        clearImportReceipt: true,
        inventorySession: incomingInventory.session,
        inventoryHistory: incomingHistory,
        clearInventorySession:
            incomingInventory.present && incomingInventory.session == null,
        iphoneSupplement: incomingSupplement,
        clearIPhoneSupplement: incomingSupplement == null,
      );
      await syncReservationNotifications(books, incoming);
      if (mounted) {
        setState(() {
          books = incoming;
          if (incomingStudents != null) students = incomingStudents;
          if (incomingMembers != null) members = incomingMembers;
          loanSettings = incomingSettings;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Yedek geri yüklendi.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yedek okunamadı veya biçimi desteklenmiyor.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> inspectIphone() async {
    if (saving || loading || error != null) return;
    setState(() => saving = true);
    try {
      // Kotlin arşivi önbelleğe akışla kopyalar ve yolunu döndürür; 150 MB+
      // kapaklı arşiv belleğe tek parça alınmaz.
      final path = await const MethodChannel(
        'kitapbul/files',
      ).invokeMethod<String>('inspectIphone');
      if (path == null || !mounted) return;
      final docs = await getApplicationDocumentsDirectory();
      final imagesPath = '${docs.path}/book-images';
      // Doğrulama turu: hiçbir şey yazılmaz, referanslar yalnız hesaplanır.
      final preview = await _runIPhoneImportPass(path, null);
      if (!mounted) return;
      final incoming = preview.books;
      final incomingStudents = preview.students;
      final incomingMembers = preview.members;
      final incomingSupplement = preview.supplement;
      final blockedReason = preview.blockedReason;
      final scanNote = preview.scanFiles > 0
          ? ' iPhone tarama kayıtları (${preview.scanFiles} dosya) Android\'de henüz gösterilmez; bayt bayt ayrı klasörde saklanır.'
          : '';
      final imageNote = preview.images > 0
          ? ' ${preview.images} kapak/arka kapak görseli aktarılacak.'
          : '';
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('iPhone yedeği incelendi'),
          content: Text(
            'Bütünlük doğrulandı. ${preview.summaryBooks} kitap, ${preview.summaryLoans} etkin ödünç ve ${preview.summaryEntries} arşiv dosyası bulundu. ${blockedReason == null ? 'Desteklenen kayıtlar aktarılabilir.$imageNote$scanNote${incomingSupplement?.isNotEmpty == true ? ' Ödünç ayarları ve kademe kuralları uygulanır. Diğer iPhone ayarları ve destek dosyaları yedekte korunur, ancak Android üzerinde henüz uygulanmaz.' : ''}' : 'Aktarım yapılamıyor: $blockedReason. Mevcut katalog değiştirilmedi.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Kapat'),
            ),
            if (incoming != null)
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Aktarımı incele'),
              ),
          ],
        ),
      );
      if (proceed != true || incoming == null || !mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kataloğu değiştir'),
          content: Text(
            '${incoming.length} kitap${incomingStudents == null ? '' : ', ${incomingStudents.length} öğrenci'}${incomingMembers == null ? '' : ', ${incomingMembers.length} üye'} içe aktarılacak. ${incomingStudents == null ? 'Mevcut öğrenciler korunacak. ' : 'Mevcut öğrenci listesi değiştirilecek. '}${incomingMembers == null ? 'Mevcut üyeler korunacak. ' : 'Mevcut üye listesi değiştirilecek. '}Mevcut katalog önce doğrulanmış ayrı bir dosyaya kopyalanır ve bu kopya silinmez. iPhone yedeğinin orijinalini saklayın.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aktar'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      final store = CatalogStore(docs);
      // Doğrulanmış yedek olmadan mevcut kayıtlar değiştirilmez: kopyalama
      // veya doğrulama başarısızsa istisna aktarımı burada durdurur.
      await store.snapshotBeforeIPhoneImport();
      final written = await _runIPhoneImportPass(
        path,
        imagesPath,
        preserveDir: '${docs.path}/iphone-preserved',
      );
      final imported = written.books;
      // Yalnız kitap sayısı değil, kitap/öğrenci/üye/ayar içeriğinin tamamı
      // onaylanan önizlemeyle aynı olmalı; kaydedilen her şey yazma turundan.
      if (imported == null || written.fingerprint != preview.fingerprint) {
        throw const FormatException('Arşiv iki okuma arasında değişti');
      }
      final writtenStudents = written.students;
      final writtenMembers = written.members;
      final writtenSupplement = written.supplement;
      // Ayarlar kayıttan önce çözülür; hata olursa katalog hiç yazılmaz.
      final writtenLoanSettings = writtenSupplement == null
          ? null
          : LoanSettings.fromSupplement(writtenSupplement);
      await store.save(
        imported,
        students: writtenStudents,
        members: writtenMembers,
        clearImportReceipt: true,
        iphoneSupplement: writtenSupplement?.isEmpty == true
            ? null
            : writtenSupplement,
        clearIPhoneSupplement:
            writtenSupplement == null || writtenSupplement.isEmpty,
      );
      // Katalog artık diskte: ekran durumu hemen yeni kayıtlara geçer. Bundan
      // sonraki bir hata "katalog değiştirilmedi" olarak gösterilemez.
      final previousBooks = books;
      if (mounted) {
        setState(() {
          books = imported;
          if (writtenStudents != null) students = writtenStudents;
          if (writtenMembers != null) members = writtenMembers;
          if (writtenLoanSettings != null) loanSettings = writtenLoanSettings;
        });
      }
      var notificationNote = '';
      try {
        await syncReservationNotifications(previousBooks, imported);
      } catch (_) {
        notificationNote =
            ' Rezervasyon bildirimleri güncellenemedi; katalog aktarıldı.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'iPhone katalog kayıtları aktarıldı (${written.images} görsel).$notificationNote',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Arşiv okunamadı, doğrulanamadı veya 512 MB sınırını aşıyor. Mevcut katalog değiştirilmedi.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget coverThumbnail(Map<String, dynamic> book) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: BookCoverWidget(book: book, width: 84, height: 122),
  );

  Future<void> showClassSummary() async {
    final classes = summarizeClasses(books);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sınıflara göre ödünçler'),
        content: SizedBox(
          width: double.maxFinite,
          child: classes.isEmpty
              ? const Text('Etkin ödünç bulunmuyor.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: classes.length,
                  itemBuilder: (ctx, i) {
                    final item = classes[i];
                    return ListTile(
                      title: Text(item.name),
                      subtitle: Text(
                        '${item.total} etkin ödünç · ${item.overdue} gecikmiş',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Future<void> enableLoanReminders() async {
    try {
      final allowed =
          await ReservationNotifications.channel.invokeMethod<bool>(
            'requestLoan',
          ) ??
          false;
      if (!mounted) return;
      if (allowed) {
        await LoanReminderService().synchronize(books);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'İade hatırlatmaları planlandı. Android, bildirim saatini pil ayarlarına göre geciktirebilir.',
              ),
            ),
          );
      } else {
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Bildirim izni kapalı'),
            content: const Text(
              'İade hatırlatmaları için Android bildirim iznini açabilirsiniz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Kapat'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ayarları aç'),
              ),
            ],
          ),
        );
        if (openSettings == true)
          await ReservationNotifications.channel.invokeMethod<bool>('settings');
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İade hatırlatmaları planlanamadı.')),
        );
    }
  }

  Future<void> showLoanSettings() async {
    if (saving) return;
    var days = loanSettings.days;
    var maximum = loanSettings.maximum;
    var block = loanSettings.blockOverdue;
    final selected = await showDialog<LoanSettings>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('Ödünç ayarları'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: days,
                  decoration: const InputDecoration(
                    labelText: 'Ödünç süresi (gün)',
                  ),
                  items: [
                    for (var day = 1; day <= 180; day++)
                      DropdownMenuItem(value: day, child: Text('$day')),
                  ],
                  onChanged: (v) => refresh(() => days = v!),
                ),
                DropdownButtonFormField<int>(
                  initialValue: maximum,
                  decoration: const InputDecoration(
                    labelText: 'Kişi başı kitap sınırı',
                  ),
                  items: [
                    for (var limit = 0; limit <= 20; limit++)
                      DropdownMenuItem(
                        value: limit,
                        child: Text(limit == 0 ? 'Sınır yok' : '$limit'),
                      ),
                  ],
                  onChanged: (v) => refresh(() => maximum = v!),
                ),
                SwitchListTile(
                  title: const Text('Gecikmesi olana yeni kitap verme'),
                  value: block,
                  onChanged: (v) => refresh(() => block = v),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Future<void>.delayed(Duration.zero);
                    if (!mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ClassLoanPage(
                          books: books,
                          students: students,
                          settings: loanSettings,
                          save: (updated) async {
                            try {
                              final previous = books;
                              await CatalogStore(
                                await getApplicationDocumentsDirectory(),
                              ).save(updated);
                              if (mounted) setState(() => books = updated);
                              await syncReservationNotifications(
                                previous,
                                updated,
                              );
                              return true;
                            } catch (_) {
                              return false;
                            }
                          },
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Sınıfa toplu ödünç'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Future<void>.delayed(Duration.zero);
                    if (!mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TextbookPage(
                          books: books,
                          students: students,
                          save: (updated) async {
                            try {
                              final previous = books;
                              await CatalogStore(
                                await getApplicationDocumentsDirectory(),
                              ).save(updated);
                              if (mounted) setState(() => books = updated);
                              await syncReservationNotifications(
                                previous,
                                updated,
                              );
                              return true;
                            } catch (_) {
                              return false;
                            }
                          },
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Ders kitabı dağıtımı'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Future<void>.delayed(Duration.zero);
                    if (mounted) await showInventory();
                  },
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Envanter sayımı'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Future<void>.delayed(Duration.zero);
                    if (mounted)
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => StudentCardsPage(students: students),
                        ),
                      );
                  },
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Öğrenci kartları'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Future<void>.delayed(Duration.zero);
                    if (mounted)
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReadingChampionsPage(
                            books: books,
                            students: students,
                          ),
                        ),
                      );
                  },
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Okuma şampiyonları'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Future<void>.delayed(Duration.zero);
                    if (mounted) await showMemberRules();
                  },
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Üye kuralları'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Future<void>.delayed(Duration.zero);
                    if (mounted) await enableLoanReminders();
                  },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('İade hatırlatmaları'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                LoanSettings(
                  days: days,
                  maximum: maximum,
                  blockOverdue: block,
                  gradeRules: loanSettings.gradeRules,
                  memberRules: loanSettings.memberRules,
                ),
              ),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => saving = true);
    try {
      final store = CatalogStore(await getApplicationDocumentsDirectory());
      final supplement = selected.writeTo(await store.loadIPhoneSupplement());
      await store.save(books, students: students, iphoneSupplement: supplement);
      if (mounted) setState(() => loanSettings = selected);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ödünç ayarları kaydedilemedi.')),
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> showMemberRules() async {
    while (mounted && !saving) {
      final rules = loanSettings.memberRules;
      final kind = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Üye ödünç kuralları'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Her üye türü için süre ve kitap sınırı belirleyebilirsiniz. Özel kural yoksa genel ayarlar uygulanır.',
                  ),
                  ...memberKinds.entries.map((entry) {
                    final rule = loanSettings.memberRuleFor(entry.key);
                    return ListTile(
                      title: Text(entry.value),
                      subtitle: Text(
                        rule == null
                            ? 'Genel kural'
                            : '${rule.days} gün · ${rule.maximum == 0 ? 'sınırsız' : '${rule.maximum} kitap'}',
                      ),
                      onTap: () => Navigator.pop(ctx, entry.key),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
      if (kind == null || !mounted) return;
      final existing = loanSettings.memberRuleFor(kind);
      var days = (existing?.days ?? 15).toString();
      var maximum = (existing?.maximum ?? 3).toString();
      String? error;
      final decision = await showDialog<Object>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, refresh) => AlertDialog(
            title: Text('${memberKinds[kind]} kuralı'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: days,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Süre (1–365 gün)',
                    ),
                    onChanged: (v) => days = v,
                  ),
                  TextFormField(
                    initialValue: maximum,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Kitap sınırı (0: sınırsız)',
                    ),
                    onChanged: (v) => maximum = v,
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              if (existing != null)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  child: const Text('Genel kurala dön'),
                ),
              FilledButton(
                onPressed: () {
                  final d = int.tryParse(days), m = int.tryParse(maximum);
                  if (d == null ||
                      d < 1 ||
                      d > 365 ||
                      m == null ||
                      m < 0 ||
                      m > 99) {
                    refresh(
                      () => error = '1–365 gün ve 0–99 kitap sınırı girin.',
                    );
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    MemberLoanRule(kind: kind, days: d, maximum: m),
                  );
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
        ),
      );
      if (decision == null || !mounted) continue;
      final updated = rules.where((rule) => rule.kind != kind).toList();
      if (decision is MemberLoanRule)
        updated.add(decision);
      else if (decision != 'delete')
        continue;
      final next = LoanSettings(
        days: loanSettings.days,
        maximum: loanSettings.maximum,
        blockOverdue: loanSettings.blockOverdue,
        gradeRules: loanSettings.gradeRules,
        memberRules: updated,
      );
      setState(() => saving = true);
      try {
        final store = CatalogStore(await getApplicationDocumentsDirectory());
        final supplement = next.writeTo(await store.loadIPhoneSupplement());
        await store.save(
          books,
          students: students,
          iphoneSupplement: supplement,
        );
        if (mounted) setState(() => loanSettings = next);
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Üye kuralları kaydedilemedi.')),
          );
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }
  }

  Future<void> showGradeRules() async {
    while (mounted && !saving) {
      final rules = loanSettings.gradeRules;
      final choice = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kademe kuralları'),
          content: SizedBox(
            width: double.maxFinite,
            child: rules.isEmpty
                ? const Text('Henüz kademe kuralı yok.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: rules.length,
                    itemBuilder: (ctx, index) {
                      final rule = rules[index];
                      return ListTile(
                        title: Text(rule.prefix),
                        subtitle: Text(
                          '${rule.days} gün · ${rule.maximum == 0 ? 'sınır yok' : '${rule.maximum} kitap'}',
                        ),
                        onTap: () => Navigator.pop(ctx, index),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: const Text('Kural ekle'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      final existing = choice < 0 ? null : rules[choice];
      var prefix = existing?.prefix ?? '';
      var days = (existing?.days ?? 15).toString();
      var maximum = (existing?.maximum ?? 3).toString();
      String? validation;
      final decision = await showDialog<Object>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, refresh) => AlertDialog(
            title: Text(
              existing == null
                  ? 'Kademe kuralı ekle'
                  : 'Kademe kuralını düzenle',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: prefix,
                    decoration: const InputDecoration(
                      labelText: 'Sınıf başlangıcı (ör. 5 veya 5-A)',
                    ),
                    onChanged: (v) => prefix = v,
                  ),
                  TextFormField(
                    initialValue: days,
                    decoration: const InputDecoration(
                      labelText: 'Süre (1–365 gün)',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => days = v,
                  ),
                  TextFormField(
                    initialValue: maximum,
                    decoration: const InputDecoration(
                      labelText: 'Kitap sınırı (0: sınırsız)',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => maximum = v,
                  ),
                  if (validation != null)
                    Text(
                      validation!,
                      style: const TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              if (existing != null)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  child: const Text('Sil'),
                ),
              FilledButton(
                onPressed: () {
                  final clean = prefix.trim();
                  final parsedDays = int.tryParse(days);
                  final parsedMaximum = int.tryParse(maximum);
                  if (clean.isEmpty ||
                      rules.any(
                        (r) => r.id != existing?.id && r.prefix == clean,
                      ) ||
                      parsedDays == null ||
                      parsedDays < 1 ||
                      parsedDays > 365 ||
                      parsedMaximum == null ||
                      parsedMaximum < 0 ||
                      parsedMaximum > 99) {
                    refresh(
                      () => validation =
                          'Tek bir sınıf başlangıcı, 1–365 gün ve 0–99 sınır girin.',
                    );
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    GradeLoanRule(
                      id: existing?.id ?? newGradeRuleId(),
                      prefix: clean,
                      maximum: parsedMaximum,
                      days: parsedDays,
                    ),
                  );
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
        ),
      );
      if (decision == null || !mounted) continue;
      final nextRules = [...rules];
      if (decision == 'delete' && existing != null) {
        nextRules.removeAt(choice);
      } else if (decision is GradeLoanRule) {
        if (existing == null) {
          nextRules.add(decision);
        } else {
          nextRules[choice] = decision;
        }
      } else {
        continue;
      }
      final next = LoanSettings(
        days: loanSettings.days,
        maximum: loanSettings.maximum,
        blockOverdue: loanSettings.blockOverdue,
        gradeRules: nextRules,
        memberRules: loanSettings.memberRules,
      );
      setState(() => saving = true);
      try {
        final store = CatalogStore(await getApplicationDocumentsDirectory());
        final supplement = next.writeTo(await store.loadIPhoneSupplement());
        await store.save(
          books,
          students: students,
          iphoneSupplement: supplement,
        );
        if (mounted) setState(() => loanSettings = next);
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kademe kuralları kaydedilemedi.')),
          );
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeCfg = appThemeNotifier.value;
    final categories = <String, String>{};
    final shelfCounts = <String, int>{};
    for (final book in books) {
      if (book['deletedAt'] != null) continue;
      final category = (book['category']?.toString() ?? '').trim();
      if (category.isNotEmpty) {
        categories.putIfAbsent(foldTurkish(category), () => category);
      }
      if ((book['isWithdrawn'] == true) == showWithdrawn) {
        final sh = (book['shelf']?.toString() ?? '').trim();
        if (sh.isNotEmpty) {
          shelfCounts[sh] = (shelfCounts[sh] ?? 0) + 1;
        }
      }
    }
    const trAlphabet = '0123456789AaBbCcÇçDdEeFfGgĞğHhIıİiJjKkLlMmNnOoÖöPpRrSsŞşTtUuÜüVvYyZz';
    int trCompare(String a, String b) {
      final minLen = a.length < b.length ? a.length : b.length;
      for (var i = 0; i < minLen; i++) {
        final ia = trAlphabet.indexOf(a[i]);
        final ib = trAlphabet.indexOf(b[i]);
        if (ia != ib) {
          if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
          return a.codeUnitAt(i).compareTo(b.codeUnitAt(i));
        }
      }
      return a.length.compareTo(b.length);
    }

    final shelfKeys = shelfCounts.keys.toList()..sort(trCompare);
    final shelfFilter = shelfCounts.containsKey(selectedShelf)
        ? selectedShelf
        : null;

    final categoryKeys = categories.keys.toList()..sort();
    final categoryFilter = categories.containsKey(selectedCategory)
        ? selectedCategory
        : null;
    final visible = books
        .where(
          (b) =>
              b['deletedAt'] == null &&
              (tab == 1 ? (b['isWithdrawn'] == true) == showWithdrawn : true) &&
              (tab != 1 ||
                  shelfFilter == null ||
                  (b['shelf']?.toString() ?? '').trim() == shelfFilter) &&
              (tab != 1 ||
                  qualityFilter == null ||
                  missingQualityField(b, qualityFilter!)) &&
              (tab != 1 ||
                  categoryFilter == null ||
                  foldTurkish((b['category']?.toString() ?? '').trim()) ==
                      categoryFilter) &&
              (tab != 1 || switch (statusFilter) {
                'available' =>
                  availableCopies(b) > 0 && b['isWithdrawn'] != true,
                'loaned' => activeLoans(b).isNotEmpty,
                'overdue' => activeLoans(b).any(isOverdue),
                'reserved' => reservationsOf(b).any(isActiveReservation),
                'favorites' => b['isFavorite'] == true,
                'textbooks' => b['isTextbook'] == true,
                _ => true,
              }) &&
              (tab == 3
                  ? matchesLoanSearch(b, query, overdueOnly: overdueOnly)
                  : matchesCatalog(b, query)),
        )
        .toList();

    if (tab == 1 && sortMode != 'default') {
      visible.sort((a, b) {
        switch (sortMode) {
          case 'title':
            return trCompare(
              (a['title'] ?? '').toString(),
              (b['title'] ?? '').toString(),
            );
          case 'author':
            return trCompare(
              (a['author'] ?? '').toString(),
              (b['author'] ?? '').toString(),
            );
          case 'shelf':
            final sc = trCompare(
              (a['shelf'] ?? '').toString(),
              (b['shelf'] ?? '').toString(),
            );
            return sc != 0
                ? sc
                : trCompare(
                    (a['title'] ?? '').toString(),
                    (b['title'] ?? '').toString(),
                  );
          case 'yearDesc':
            final ya = int.tryParse((a['publicationYear'] ?? '').toString()) ?? 0;
            final yb = int.tryParse((b['publicationYear'] ?? '').toString()) ?? 0;
            return yb.compareTo(ya);
          case 'accession':
            return (a['accessionCode'] ?? '')
                .toString()
                .compareTo((b['accessionCode'] ?? '').toString());
          case 'ratingDesc':
            final ra = (a['rating'] as int?) ?? 0;
            final rb = (b['rating'] as int?) ?? 0;
            final cmp = rb.compareTo(ra);
            return cmp != 0
                ? cmp
                : trCompare(
                    (a['title'] ?? '').toString(),
                    (b['title'] ?? '').toString(),
                  );
          case 'mostRead':
            final ca = loanHistory(
              a,
            ).where((e) => e['kind'] == 'returned' || e['kind'] == 'lent').length;
            final cb = loanHistory(
              b,
            ).where((e) => e['kind'] == 'returned' || e['kind'] == 'lent').length;
            final cmp = cb.compareTo(ca);
            return cmp != 0
                ? cmp
                : trCompare(
                    (a['title'] ?? '').toString(),
                    (b['title'] ?? '').toString(),
                  );
          case 'newest':
            return (b['id'] ?? '').toString().compareTo(
              (a['id'] ?? '').toString(),
            );
          default:
            return 0;
        }
      });
    }

    final scheme = Theme.of(context).colorScheme;
    final busy = loading || error != null || saving;
    final hasActiveFilters =
        categoryFilter != null ||
        shelfFilter != null ||
        statusFilter != 'all' ||
        showWithdrawn ||
        qualityFilter != null;
    var activeLoanCount = 0;
    var overdueLoanCount = 0;
    for (final b in books) {
      if (b['deletedAt'] != null) continue;
      final loans = activeLoans(b);
      activeLoanCount += loans.length;
      overdueLoanCount += loans.where(isOverdue).length;
    }
    final bookActions = BookActionCallbacks(
      onEdit: (b) => add(b),
      onLoan: loan,
      onReturn: showLoans,
      onExtend: extend,
      onMarkLost: markLost,
      onResolveIdentity: resolveLoanIdentity,
      onCopies: showCopies,
      onReservations: showReservations,
      onHistory: showHistory,
      onWithdraw: changeWithdrawal,
      onTrash: trashBook,
      onOpenCover: openBookCoverLightbox,
      onToggleFavorite: toggleFavorite,
      onRateBook: rateBook,
      onQuickExtend: quickExtendLoan,
      allBooks: books,
    );

    void openDiscovery() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LibraryDiscoveryPage(
            books: books,
            actions: bookActions,
          ),
        ),
      );
    }

    void openSanctuary() {
      openReadingSanctuaryPage(
        context,
        books: books,
        onOpenBook: (b) => showRichBookDetailSheet(context, b, bookActions),
      );
    }

    void openThemeStudio() {
      showThemeAndSchoolSettingsSheet(
        context,
        totalBooks: books.where((b) => b['deletedAt'] == null).length,
        onResyncIPhoneSeed: resyncBundledIPhoneCatalog,
      );
    }

    final selectedBooks = selectionMode
        ? books.where((b) => selectedBookIds.contains(b['id'])).toList()
        : const <Map<String, dynamic>>[];

    return AmbientLibraryBackground(
      wallpaperAsset: themeCfg.wallpaperAsset,
      particlesEnabled: themeCfg.particlesEnabled,
      clarity: themeCfg.clarity,
      effectIntensity: themeCfg.effectIntensity,
      tapRipplesEnabled: themeCfg.tapRipplesEnabled,
      scrollOffsetListenable: _scrollParallax,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: (tab == 1 && selectionMode)
          ? AppBar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              leading: IconButton(
                tooltip: 'Seçimi İptal Et',
                icon: const Icon(Icons.close_rounded),
                onPressed: clearBookSelection,
              ),
              title: Text(
                '${selectedBookIds.length} kitap seçili',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              actions: [
                IconButton(
                  tooltip: 'Görünenlerin Tümünü Seç',
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: () {
                    setState(() {
                      for (final b in visible) {
                        final id = '${b['id'] ?? ''}';
                        if (id.isNotEmpty) selectedBookIds.add(id);
                      }
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Toplu Raf Taşı',
                  icon: const Icon(Icons.shelves),
                  onPressed: saving
                      ? null
                      : () => _batchUpdateBookField(
                          title: 'Toplu Raf / Dolap Taşı',
                          fieldLabel: 'Yeni Dolap / Raf',
                          fieldKey: 'shelf',
                          suggestions: topFieldSuggestions(books, 'shelf'),
                        ),
                ),
                IconButton(
                  tooltip: 'Toplu Kategori Ata',
                  icon: const Icon(Icons.category_outlined),
                  onPressed: saving
                      ? null
                      : () => _batchUpdateBookField(
                          title: 'Toplu Kategori Ata',
                          fieldLabel: 'Kategori',
                          fieldKey: 'category',
                          suggestions: topFieldSuggestions(books, 'category'),
                        ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Diğer Toplu İşlemler',
                  onSelected: (action) {
                    switch (action) {
                      case 'labels':
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                LibraryLabelsPage(books: selectedBooks),
                          ),
                        );
                      case 'export_xlsx':
                        exportCatalogXlsx(selectedBooks);
                      case 'trash':
                        _batchMoveToTrash();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'labels',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.qr_code_2_rounded),
                        title: Text('Seçili Kitaplar İçin Etiket Bas'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export_xlsx',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.grid_on_rounded),
                        title: Text('Seçilenleri Excel İndir'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'trash',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('Seçilenleri Çöpe Taşı'),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : AppBar(
        centerTitle: false,
        titleSpacing: 12,
        backgroundColor: scheme.surface.withValues(
          alpha: themeCfg.glassCardsEnabled ? 0.68 : 0.94,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [themeCfg.preset.seed, themeCfg.preset.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: themeCfg.preset.seed.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_stories_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Kitap Bul',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16.5,
                      height: 1.1,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    themeCfg.libraryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: busy ? null : openSanctuary,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        themeCfg.preset.seed.withValues(alpha: 0.90),
                        themeCfg.preset.secondary.withValues(alpha: 0.90),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.34),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: themeCfg.preset.seed.withValues(alpha: 0.28),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '☽',
                        style: TextStyle(
                          color: Color(0xFFFDE68A),
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Okuma',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Atmosfer & Tema Stüdyosu',
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            padding: EdgeInsets.zero,
            onPressed: busy ? null : openThemeStudio,
            icon: const Icon(Icons.auto_awesome_rounded, size: 20),
          ),
          PopupMenuButton<String>(
            tooltip: 'Yedekleme ve otomasyon',
            enabled: !busy,
            padding: EdgeInsets.zero,
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.more_vert_rounded, size: 21),
            onSelected: (action) {
              switch (action) {
                case 'sanctuary':
                  openSanctuary();
                case 'theme_studio':
                  openThemeStudio();
                case 'trash':
                  showTrash();
                case 'discover':
                  openDiscovery();
                case 'ai_settings':
                  showAiProxySettingsSheet(context);
                case 'voice_assistant':
                  openVoiceAssistant();
                case 'bulk_isbn':
                  openBulkIsbnImporter();
                case 'four_page_ocr':
                  openFourPageVision();
                case 'shelf_photo':
                  openShelfPhotoScanner();
                case 'labels':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LibraryLabelsPage(books: books),
                    ),
                  );
                case 'duty':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SchoolDutyRosterPage(
                        students: students,
                        initialRoster: dutyRoster,
                        onChanged: (r) => setState(() => dutyRoster = r),
                      ),
                    ),
                  );
                case 'inventory':
                  showInventory();
                case 'export_xlsx':
                  exportCatalogXlsx(
                    tab == 1 && visible.isNotEmpty ? visible : books,
                  );
                case 'import_xlsx':
                  importCatalogXlsx();
                case 'export_csv':
                  exportCatalogCsv();
                case 'export_pdf':
                  exportCatalogPdf();
                case 'export_zip':
                  exportCatalog();
                case 'import_backup':
                  importCatalog();
                case 'iphone':
                  inspectIphone();
                case 'resync_iphone':
                  resyncBundledIPhoneCatalog();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'sanctuary',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.nightlight_round, color: Color(0xFF4F46E5)),
                  title: Text('Huzurlu Okuma Köşesi (Odak)'),
                ),
              ),
              PopupMenuItem(
                value: 'theme_studio',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.palette_outlined, color: Color(0xFFD97706)),
                  title: Text('Atmosfer & Tema Stüdyosu'),
                ),
              ),
              PopupMenuItem(
                value: 'discover',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.explore_rounded, color: Color(0xFFDB2777)),
                  title: Text('Ne Okusam? · Seriler & Yazarlar'),
                ),
              ),
              PopupMenuItem(
                value: 'trash',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Çöp Kutusu'),
                ),
              ),
              PopupMenuItem(
                value: 'ai_settings',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.hub_rounded, color: Color(0xFF0284C7)),
                  title: Text('CLIProxyAPI & Gemini Ayarları'),
                ),
              ),
              PopupMenuItem(
                value: 'voice_assistant',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.mic_rounded, color: Color(0xFF06B6D4)),
                  title: Text('Sesli Yapay Zekâ Asistanı'),
                ),
              ),
              PopupMenuItem(
                value: 'bulk_isbn',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.rocket_launch_rounded, color: Color(0xFFEA580C)),
                  title: Text('100+ ISBN Toplu Amazon Çekme'),
                ),
              ),
              PopupMenuItem(
                value: 'four_page_ocr',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.document_scanner_rounded, color: Color(0xFF9333EA)),
                  title: Text('4-Sayfa Kapak & İç Künye OCR'),
                ),
              ),
              PopupMenuItem(
                value: 'shelf_photo',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.collections_bookmark_rounded, color: Color(0xFF1D4ED8)),
                  title: Text('Raf Fotoğrafından Toplu Kitap Sayma'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'labels',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.qr_code_2_rounded, color: Color(0xFF7C3AED)),
                  title: Text('Sırt Etiketi, Barkod & QR Bas'),
                ),
              ),
              PopupMenuItem(
                value: 'duty',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.badge_outlined, color: Color(0xFFBE123C)),
                  title: Text('Nöbetçi Öğrenci Çizelgesi'),
                ),
              ),
              PopupMenuItem(
                value: 'inventory',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Kameralı Envanter Sayımı'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'export_xlsx',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.grid_on_rounded, color: Color(0xFF15803D)),
                  title: Text('Excel (.xlsx) Kitap Listesi İndir'),
                ),
              ),
              PopupMenuItem(
                value: 'import_xlsx',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.upload_file_rounded),
                  title: Text('Excel (.xlsx) Tablodan Yükle'),
                ),
              ),
              PopupMenuItem(
                value: 'export_csv',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.table_view_outlined),
                  title: Text('Kataloğu CSV Kaydet'),
                ),
              ),
              PopupMenuItem(
                value: 'export_pdf',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Kataloğu PDF Kaydet'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'export_zip',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.save_alt_rounded),
                  title: Text('Tam Katalog Yedeği Kaydet (.zip)'),
                ),
              ),
              PopupMenuItem(
                value: 'import_backup',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_backup_restore_rounded),
                  title: Text('Katalog Yedeğini Geri Yükle'),
                ),
              ),
              PopupMenuItem(
                value: 'iphone',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.find_in_page_outlined),
                  title: Text('Haricî iPhone ZIP Yedeği Aktar'),
                ),
              ),
              PopupMenuItem(
                value: 'resync_iphone',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sync_rounded),
                  title: Text('2.892 iPhone Kitabını Eşitle'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical) {
            _scrollParallax.value = n.metrics.pixels;
          }
          return false;
        },
        child: loading
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text(
                        loadingMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              )
            : error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: scheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(error!, textAlign: TextAlign.center),
                      if (backupAvailable) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Son yedek önceki kayda ait olabilir. Bozuk dosya ayrıca korunur.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: saving ? null : recoverBackup,
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('Son yedeği geri yükle'),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  if (saving) const LinearProgressIndicator(minHeight: 2.5),
                  if (tab == 0)
                    _buildVitrinTab(
                      context,
                      scheme: scheme,
                      themeCfg: themeCfg,
                      activeLoanCount: activeLoanCount,
                      overdueLoanCount: overdueLoanCount,
                      onOpenDiscovery: openDiscovery,
                      onOpenSanctuary: openSanctuary,
                      onOpenThemeStudio: openThemeStudio,
                    )
                  else if (tab == 1) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: FrostedGlassSurface(
                        borderRadius: 18,
                        opacity: themeCfg.glassCardsEnabled ? 0.74 : 0.92,
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: searchController,
                                onChanged: (v) => setState(() => query = v),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  hintText:
                                      'Kitap, yazar, ISBN, CAL- veya dolap ara...',
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (query.isNotEmpty)
                                        IconButton(
                                          tooltip: 'Aramayı temizle',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => setState(() {
                                            query = '';
                                            searchController.clear();
                                          }),
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 19,
                                          ),
                                        ),
                                      IconButton(
                                        tooltip: 'Katalogda barkod ara',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: scanCatalog,
                                        icon: const Icon(
                                          Icons.qr_code_scanner_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: sortMode == 'default'
                                    ? scheme.secondaryContainer.withValues(
                                        alpha: 0.78,
                                      )
                                    : scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: PopupMenuButton<String>(
                                tooltip: 'Sıralama',
                                onSelected: (v) => setState(() => sortMode = v),
                                icon: Icon(
                                  Icons.sort_by_alpha_rounded,
                                  color: sortMode == 'default'
                                      ? scheme.onSecondaryContainer
                                      : scheme.onPrimaryContainer,
                                ),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'default',
                                    child: Text('Varsayılan Sıra'),
                                  ),
                                  PopupMenuItem(
                                    value: 'title',
                                    child: Text('Kitap Adı (A → Z)'),
                                  ),
                                  PopupMenuItem(
                                    value: 'author',
                                    child: Text('Yazar Adı (A → Z)'),
                                  ),
                                  PopupMenuItem(
                                    value: 'shelf',
                                    child: Text('Dolap / Raf (A → N)'),
                                  ),
                                  PopupMenuItem(
                                    value: 'accession',
                                    child: Text('Demirbaş Kodu (CAL-)'),
                                  ),
                                  PopupMenuItem(
                                    value: 'yearDesc',
                                    child: Text('Basım Yılı (Yeni → Eski)'),
                                  ),
                                  PopupMenuItem(
                                    value: 'mostRead',
                                    child: Text('En Çok Ödünç Alınan'),
                                  ),
                                  PopupMenuItem(
                                    value: 'ratingDesc',
                                    child: Text('Yüksek Puan (5 → 1)'),
                                  ),
                                  PopupMenuItem(
                                    value: 'newest',
                                    child: Text('Son Eklenenler'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (filtersExpanded || hasActiveFilters)
                              IconButton.filled(
                                tooltip: 'Filtreler',
                                onPressed: () => setState(
                                  () => filtersExpanded = !filtersExpanded,
                                ),
                                icon: Badge(
                                  isLabelVisible: hasActiveFilters,
                                  child: const Icon(Icons.tune_rounded),
                                ),
                              )
                            else
                              IconButton.filledTonal(
                                tooltip: 'Filtreler',
                                onPressed: () => setState(
                                  () => filtersExpanded = !filtersExpanded,
                                ),
                                icon: const Icon(Icons.tune_rounded),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Hızlı Durum Filtreleri
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        children: [
                          for (final item in const [
                            (id: 'all', label: 'Tümü'),
                            (id: 'available', label: 'Rafta'),
                            (id: 'loaned', label: 'Ödünçte'),
                            (id: 'overdue', label: 'Geciken'),
                            (id: 'reserved', label: 'Rezerveli'),
                            (id: 'favorites', label: 'Favoriler'),
                            (id: 'textbooks', label: 'Ders Kitabı'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  item.label,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                selected: statusFilter == item.id,
                                onSelected: (_) => setState(
                                  () => statusFilter = statusFilter == item.id &&
                                          item.id != 'all'
                                      ? 'all'
                                      : item.id,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Hızlı Dolap / Raf Filtre Çubuğu (Dolap A .. Dolap N)
                    if (shelfKeys.isNotEmpty)
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                visualDensity: VisualDensity.compact,
                                label: const Text(
                                  'Tüm Dolaplar',
                                  style: TextStyle(fontSize: 11.5),
                                ),
                                selected: shelfFilter == null,
                                onSelected: (_) =>
                                    setState(() => selectedShelf = null),
                              ),
                            ),
                            for (final sh in shelfKeys)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    '${sh.length <= 2 ? 'Dolap $sh' : sh} (${shelfCounts[sh]})',
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  selected: shelfFilter == sh,
                                  onSelected: (sel) => setState(
                                    () => selectedShelf = sel ? sh : null,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: (filtersExpanded || hasActiveFilters)
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (categories.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: DropdownButtonFormField<String>(
                                        key: ValueKey(categoryFilter),
                                        initialValue: categoryFilter,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          labelText: 'Kategori Filtresi',
                                        ),
                                        hint: const Text('Tüm kategoriler'),
                                        items: [
                                          const DropdownMenuItem<String>(
                                            value: null,
                                            child: Text('Tüm kategoriler'),
                                          ),
                                          ...categoryKeys.map(
                                            (key) => DropdownMenuItem(
                                              value: key,
                                              child: Text(categories[key]!),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) => setState(
                                          () => selectedCategory = value,
                                        ),
                                      ),
                                    ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      FilterChip(
                                        label: const Text('Düşülen kitaplar'),
                                        selected: showWithdrawn,
                                        onSelected: (value) => setState(() {
                                          showWithdrawn = value;
                                          if (value) qualityFilter = null;
                                        }),
                                      ),
                                      ActionChip(
                                        avatar: const Icon(
                                          Icons.fact_check_outlined,
                                          size: 17,
                                        ),
                                        label: const Text('Eksik alanları tara'),
                                        onPressed: saving
                                            ? null
                                            : openDataQuality,
                                      ),
                                      if (qualityFilter != null)
                                        InputChip(
                                          label: Text(
                                            'Eksik: ${qualityFilter!.label}',
                                          ),
                                          onDeleted: () => setState(
                                            () => qualityFilter = null,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer.withValues(
                                alpha: 0.65,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${visible.length} kitap',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          if (hasActiveFilters) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Filtreleri Temizle',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              onPressed: () => setState(() {
                                selectedCategory = null;
                                selectedShelf = null;
                                statusFilter = 'all';
                                showWithdrawn = false;
                                qualityFilter = null;
                              }),
                              icon: Icon(
                                Icons.filter_alt_off_rounded,
                                size: 17,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                          if (visible.isNotEmpty &&
                              viewMode != CatalogViewMode.excelTable) ...[
                            const SizedBox(width: 2),
                            IconButton(
                              tooltip: selectionMode
                                  ? 'Seçimi Kapat'
                                  : 'Toplu Seçim Modu',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              onPressed: () {
                                if (selectionMode) {
                                  clearBookSelection();
                                } else {
                                  setState(() => _selectionActive = true);
                                }
                              },
                              icon: Icon(
                                selectionMode
                                    ? Icons.check_box_rounded
                                    : Icons.checklist_rounded,
                                size: 18,
                                color: selectionMode
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(width: 6),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SegmentedButton<CatalogViewMode>(
                                  showSelectedIcon: false,
                                  style: ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: WidgetStateProperty.all(
                                      const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                  ),
                                  segments: [
                                    for (final m in CatalogViewMode.values)
                                      ButtonSegment<CatalogViewMode>(
                                        value: m,
                                        icon: Icon(m.icon, size: 17),
                                        label: Text(
                                          m.label,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                  selected: {viewMode},
                                  onSelectionChanged: (next) {
                                    HapticFeedback.selectionClick();
                                    setState(() => viewMode = next.first);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: visible.isEmpty
                            ? Builder(
                                key: const ValueKey('empty'),
                                builder: (_) {
                                  final catalogEmpty = !books.any(
                                    (b) => b['deletedAt'] == null,
                                  );
                                  return EmptyCatalogArtwork(
                                    title: catalogEmpty
                                        ? 'Kütüphaneniz Hazır!'
                                        : 'Eşleşen Kitap Bulunamadı',
                                    subtitle: catalogEmpty
                                        ? 'Barkod okutarak, Amazon/Kitapyurdu\'ndan çekerek veya Excel (.xlsx) listenizi yükleyerek başlayın.'
                                        : 'Arama terimini veya seçili dolap/kategori filtrelerini değiştirerek tekrar deneyin.',
                                    onQuickRegister: catalogEmpty && !saving
                                        ? showQuickRegister
                                        : null,
                                    onAddBook: catalogEmpty && !saving
                                        ? () => add()
                                        : null,
                                    onImportXlsx: catalogEmpty && !saving
                                        ? importCatalogXlsx
                                        : null,
                                  );
                                },
                              )
                            : switch (viewMode) {
                                CatalogViewMode.showcaseGrid =>
                                  CatalogShowcaseGridView(
                                    key: const ValueKey('showcaseGrid'),
                                    books: visible,
                                    actions: bookActions,
                                    selectedIds: selectedBookIds,
                                    selectionMode: selectionMode,
                                    onToggleSelect: toggleBookSelection,
                                  ),
                                CatalogViewMode.largeCards =>
                                  CatalogLargeCardsView(
                                    key: const ValueKey('largeCards'),
                                    books: visible,
                                    actions: bookActions,
                                    selectedIds: selectedBookIds,
                                    selectionMode: selectionMode,
                                    onToggleSelect: toggleBookSelection,
                                  ),
                                CatalogViewMode.bookshelf =>
                                  CatalogBookshelfView(
                                    key: const ValueKey('bookshelf'),
                                    books: visible,
                                    actions: bookActions,
                                    selectedIds: selectedBookIds,
                                    selectionMode: selectionMode,
                                    onToggleSelect: toggleBookSelection,
                                  ),
                                CatalogViewMode.excelTable =>
                                  CatalogExcelTableView(
                                    key: const ValueKey('excelTable'),
                                    books: visible,
                                    actions: bookActions,
                                    busy: saving,
                                    onExportXlsx: () =>
                                        exportCatalogXlsx(visible),
                                    onImportXlsx: importCatalogXlsx,
                                    onExportCsv: exportCatalogCsv,
                                    onExportPdf: exportCatalogPdf,
                                  ),
                              },
                      ),
                    ),
                  ] else if (tab == 2)
                    Expanded(
                      child: CirculationDeskView(
                        books: books,
                        students: students,
                        members: members,
                        loanSettings: loanSettings,
                        dutyRoster: dutyRoster,
                        busy: saving,
                        actions: bookActions,
                        onSaveBooks: save,
                        onOpenDutyRoster: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SchoolDutyRosterPage(
                              students: students,
                              initialRoster: dutyRoster,
                              onChanged: (r) => setState(() => dutyRoster = r),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (tab == 3) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                      child: TextField(
                        controller: searchController,
                        onChanged: (v) => setState(() => query = v),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: 'Ödünç kitap, öğrenci veya sınıf ara...',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (query.isNotEmpty)
                                IconButton(
                                  tooltip: 'Aramayı temizle',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() {
                                    query = '';
                                    searchController.clear();
                                  }),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 19,
                                  ),
                                ),
                              IconButton(
                                tooltip: 'Barkod ile ara',
                                visualDensity: VisualDensity.compact,
                                onPressed: scanCatalog,
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ModernLoansTabView(
                        visibleBooks: visible,
                        overdueOnly: overdueOnly,
                        busy: saving,
                        onToggleOverdue: (value) =>
                            setState(() => overdueOnly = value),
                        onStudents: showStudents,
                        onClassLoan: openClassLoan,
                        onTextbooks: openTextbooks,
                        onChampions: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReadingChampionsPage(
                              books: books,
                              students: students,
                            ),
                          ),
                        ),
                        onStudentCards: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StudentCardsPage(students: students),
                          ),
                        ),
                        onClassSummary: showClassSummary,
                        onLoanSettings: showLoanSettings,
                        onGradeRules: showGradeRules,
                        actions: bookActions,
                      ),
                    ),
                  ] else
                    Expanded(
                      child: SchoolAutomationHubView(
                        books: books,
                        students: students,
                        dutyRoster: dutyRoster,
                        busy: saving,
                        onSaveBooks: save,
                        onDutyChanged: (r) => setState(() => dutyRoster = r),
                        onOpenInventory: showInventory,
                        onOpenChampions: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReadingChampionsPage(
                              books: books,
                              students: students,
                            ),
                          ),
                        ),
                        onOpenTextbooks: openTextbooks,
                        onOpenDataQuality: openDataQuality,
                        onExportXlsx: () => exportCatalogXlsx(books),
                        onResyncIPhoneSeed: resyncBundledIPhoneCatalog,
                        onSaveInventorySession: saveShelfInventorySession,
                        onOpenDiscovery: openDiscovery,
                        onOpenSanctuary: openSanctuary,
                        onOpenThemeStudio: openThemeStudio,
                      ),
                    ),
                ],
              ),
      ),
      floatingActionButton: error == null && !loading && tab == 1
          ? FloatingActionButton.extended(
              onPressed: saving ? null : () => add(),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Kitap Ekle',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer.withValues(
            alpha: themeCfg.glassCardsEnabled ? 0.80 : 0.96,
          ),
          border: Border(
            top: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.14)
                  : scheme.outlineVariant.withValues(alpha: 0.42),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 11.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                overflow: TextOverflow.ellipsis,
              );
            }),
          ),
          child: NavigationBar(
            height: 68,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            selectedIndex: tab,
            onDestinationSelected: (v) {
              HapticFeedback.selectionClick();
              setState(() => tab = v);
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Vitrin',
              ),
              const NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book_rounded),
                label: 'Kitaplar',
              ),
              const NavigationDestination(
                icon: Icon(Icons.point_of_sale_outlined),
                selectedIcon: Icon(Icons.point_of_sale_rounded),
                label: 'Banko',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: activeLoanCount > 0,
                  backgroundColor: overdueLoanCount > 0
                      ? scheme.error
                      : scheme.primary,
                  label: Text('$activeLoanCount'),
                  child: const Icon(Icons.swap_horiz_rounded),
                ),
                selectedIcon: Badge(
                  isLabelVisible: activeLoanCount > 0,
                  backgroundColor: overdueLoanCount > 0
                      ? scheme.error
                      : scheme.primary,
                  label: Text('$activeLoanCount'),
                  child: const Icon(Icons.swap_horizontal_circle_rounded),
                ),
                label: 'Ödünç',
              ),
              const NavigationDestination(
                icon: Icon(Icons.dashboard_customize_outlined),
                selectedIcon: Icon(Icons.dashboard_customize_rounded),
                label: 'Atölye',
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  /// Secde Vakti kalibresinde animasyonlu ana vitrin ve resimli hızlı erişim sekmesi.
  Widget _buildVitrinTab(
    BuildContext context, {
    required ColorScheme scheme,
    required AppThemeSettings themeCfg,
    required int activeLoanCount,
    required int overdueLoanCount,
    required VoidCallback onOpenDiscovery,
    required VoidCallback onOpenSanctuary,
    required VoidCallback onOpenThemeStudio,
  }) {
    final activeBookCount = books
        .where((b) => b['deletedAt'] == null && b['isWithdrawn'] != true)
        .length;

    return Expanded(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          LibraryHeroHeader(
            books: books,
            libraryTitle: '${themeCfg.schoolName} · ${themeCfg.libraryName}',
            collapsed: heroCollapsed,
            showQuickRibbon: false,
            onToggleCollapsed: () =>
                setState(() => heroCollapsed = !heroCollapsed),
            busy: saving,
            onOpenDesk: () => setState(() => tab = 2),
            onOpenLabels: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LibraryLabelsPage(books: books),
              ),
            ),
            onVoiceAssistant: openVoiceAssistant,
            onBulkIsbnAmazon: openBulkIsbnImporter,
            onFourPageOcr: openFourPageVision,
            onShelfPhotoCount: openShelfPhotoScanner,
            onQuickRegister: showQuickRegister,
            onKitapyurduSearch: searchKitapyurduAndRegister,
            onInventory: showInventory,
            onExportXlsx: () => exportCatalogXlsx(books),
            onImportXlsx: importCatalogXlsx,
            onDataQuality: openDataQuality,
            onDiscover: onOpenDiscovery,
            onOpenSanctuary: onOpenSanctuary,
            onOpenThemeStudio: onOpenThemeStudio,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
            child: FrostedGlassSurface(
              borderRadius: 22,
              opacity: themeCfg.glassCardsEnabled ? 0.72 : 0.90,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              themeCfg.preset.seed,
                              themeCfg.preset.secondary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Kitaplar Listesi',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              '$activeBookCount kitap • Tam ekran katalog penceresi',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => tab = 1);
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text(
                          'Listeyi Aç',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchController,
                    onChanged: (v) => setState(() => query = v),
                    onSubmitted: (_) => setState(() => tab = 1),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Kitap, yazar, ISBN veya CAL- ara ve listeye geç...',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (query.isNotEmpty)
                            IconButton(
                              tooltip: 'Aramayı temizle',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() {
                                query = '';
                                searchController.clear();
                              }),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          IconButton(
                            tooltip: 'Barkod ile katalogda bul',
                            visualDensity: VisualDensity.compact,
                            onPressed: scanCatalog,
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                          ),
                          IconButton(
                            tooltip: 'Kitaplar sekmesine geç',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => tab = 1),
                            icon: Icon(
                              Icons.arrow_forward_rounded,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Kütüphane Vitrini & Modüller',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [
                IllustratedSquareMenuCard(
                  title: 'Kitaplar Listesi',
                  subtitle: '$activeBookCount eser • Filtre & dolap görünümü',
                  imageAsset: 'assets/images/library_hero.jpg',
                  icon: Icons.menu_book_rounded,
                  badge: '$activeBookCount KİTAP',
                  accentColors: const [Color(0xFF92400E), Color(0xFFF59E0B)],
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => tab = 1);
                  },
                ),
                IllustratedSquareMenuCard(
                  title: 'Okuma Köşesi',
                  subtitle: 'Huzurlu odak sayacı • Günün tavsiyesi',
                  imageAsset: 'assets/images/card_okuma_modu.webp',
                  icon: Icons.nightlight_round,
                  badge: 'ODAKLAN',
                  accentColors: const [Color(0xFF312E81), Color(0xFF6366F1)],
                  onTap: saving ? null : onOpenSanctuary,
                ),
                IllustratedSquareMenuCard(
                  title: 'Ne Okusam?',
                  subtitle: 'Keşfet & rastgele eser önerisi',
                  imageAsset: 'assets/images/card_kesfet.webp',
                  icon: Icons.explore_rounded,
                  badge: 'KEŞİF',
                  accentColors: const [Color(0xFF9D174D), Color(0xFFF43F5E)],
                  onTap: saving ? null : onOpenDiscovery,
                ),
                IllustratedSquareMenuCard(
                  title: 'Atmosfer & Tema',
                  subtitle: 'Canlı sahne • Vakit senkronu & parçacıklar',
                  imageAsset: 'assets/images/bg_osmanli_kutuphane.webp',
                  icon: Icons.palette_rounded,
                  badge: 'STÜDYO',
                  accentColors: const [Color(0xFF78350F), Color(0xFFD97706)],
                  onTap: saving ? null : onOpenThemeStudio,
                ),
                IllustratedSquareMenuCard(
                  title: 'Akıllı Banko',
                  subtitle: 'Hızlı barkod ödünç & iade işlemi',
                  imageAsset: 'assets/images/bg_yildizli_kutuphane.webp',
                  icon: Icons.point_of_sale_rounded,
                  badge: activeLoanCount > 0 ? '$activeLoanCount ÖDÜNÇ' : 'BANKO',
                  accentColors: overdueLoanCount > 0
                      ? const [Color(0xFF991B1B), Color(0xFFEF4444)]
                      : const [Color(0xFF0F766E), Color(0xFF14B8A6)],
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => tab = 2);
                  },
                ),
                IllustratedSquareMenuCard(
                  title: 'Envanter & Raf',
                  subtitle: 'Dolap A-N kontrolü ve eksik analizi',
                  imageAsset: 'assets/images/card_envanter.webp',
                  icon: Icons.inventory_2_rounded,
                  badge: 'SAYIM',
                  accentColors: const [Color(0xFF065F46), Color(0xFF10B981)],
                  onTap: saving ? null : showInventory,
                ),
                IllustratedSquareMenuCard(
                  title: 'Okuma Şampiyonları',
                  subtitle: 'Öğrenci & sınıf okuma sıralaması',
                  imageAsset: 'assets/images/card_sampiyonlar.webp',
                  icon: Icons.emoji_events_rounded,
                  badge: 'LİDERLİK',
                  accentColors: const [Color(0xFFB45309), Color(0xFFFBBF24)],
                  onTap: saving
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReadingChampionsPage(
                              books: books,
                              students: students,
                            ),
                          ),
                        ),
                ),
                IllustratedSquareMenuCard(
                  title: 'Excel & Rapor',
                  subtitle: 'Kataloğu .xlsx çalışma kitabına aktar',
                  imageAsset: 'assets/images/card_excel_rapor.webp',
                  icon: Icons.table_view_rounded,
                  badge: '.XLSX',
                  accentColors: const [Color(0xFF14532D), Color(0xFF22C55E)],
                  onTap: saving ? null : () => exportCatalogXlsx(books),
                ),
                IllustratedSquareMenuCard(
                  title: '4-Sayfa AI OCR',
                  subtitle: 'Kapak ve iç künyeden otomatik kayıt',
                  imageAsset: 'assets/images/scanner_banner.jpg',
                  icon: Icons.document_scanner_rounded,
                  badge: 'AI OCR',
                  accentColors: const [Color(0xFF6B21A8), Color(0xFFD946EF)],
                  onTap: saving ? null : openFourPageVision,
                ),
                IllustratedSquareMenuCard(
                  title: 'Sesli AI Asistan',
                  subtitle: 'Türkçe sesle ara & kütüphane sorgula',
                  imageAsset: 'assets/images/voice_assistant_banner.jpg',
                  icon: Icons.mic_rounded,
                  badge: 'SESLİ AI',
                  accentColors: const [Color(0xFF0369A1), Color(0xFF06B6D4)],
                  onTap: saving ? null : openVoiceAssistant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// Üst düzey ZIP yardımcıları: State metodu içindeki kapanış `this`'i
/// (ve gönderilemeyen alanlarını) isolate'e taşır; bu yüzden kapanış yalnız
/// burada, verilen parametrelerle kurulur.
Future<ZipBackupSummary> _runZipWrite(
  String catalogJson,
  String docsPath,
  String outPath,
) => Isolate.run(
  () => writeZipBackup(
    catalogJson: catalogJson,
    docsPath: docsPath,
    outPath: outPath,
  ),
);

Future<VerifiedZipBackup> _runZipVerify(String zipPath) =>
    Isolate.run(() => verifyZipBackup(zipPath));

Future<void> _runZipInstall(
  String zipPath,
  String docsPath,
  VerifiedZipBackup verified,
) => Isolate.run(() => installZipBackupFiles(zipPath, docsPath, verified));

/// Üst düzey yardımcı: isolate kapanışı yalnız bu parametreleri taşır
/// (State veya BuildContext gönderilmez).
Future<IPhoneImportPass> _runIPhoneImportPass(
  String path,
  String? imagesPath, {
  String? preserveDir,
}) => Isolate.run(
  () => runIPhoneImportPass(
    path,
    imagesPath: imagesPath,
    preserveDir: preserveDir,
  ),
);
