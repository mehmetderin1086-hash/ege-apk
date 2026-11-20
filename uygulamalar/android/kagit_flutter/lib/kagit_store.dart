import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'kagit_ai_service.dart';
import 'kagit_models.dart';

/// Kâğıt ana durum yöneticisi: kitaplık, klasörler, anotasyon geçmişi,
/// öğretmen sınıfları, yerel PDF/ML Kit köprüsü ve CLIProxyAPI ayarları.
class KagitController extends ChangeNotifier {
  KagitController({
    this.enableNativePlatform = true,
    this.testWorkspaceDir,
    KagitAiService? aiService,
  }) : aiService = aiService ?? KagitAiService();

  static const MethodChannel _channel = MethodChannel('com.mehmetderin.kagit/platform');
  static const Uuid _uuid = Uuid();

  final bool enableNativePlatform;
  final Directory? testWorkspaceDir;
  final KagitAiService aiService;

  late Directory _rootDir;
  late Directory _libraryDir;
  late Directory _rendersDir;
  late Directory _exportsDir;
  bool _initialized = false;

  List<KitaplikOgesi> items = [];
  List<Klasor> folders = [];
  Map<String, List<PdfAnnotation>> annotationsByDoc = {};
  final Map<String, List<List<PdfAnnotation>>> _undoStacks = {};
  final Map<String, List<List<PdfAnnotation>>> _redoStacks = {};
  List<List<NormPoint>> savedSignatureStrokes = [];
  List<KagitToolId> recentTools = [
    KagitToolId.birlestir,
    KagitToolId.imzaEkle,
    KagitToolId.ocrMetinTanima,
    KagitToolId.piiKarartma,
  ];
  List<SinifGrubu> siniflar = [];
  KagitAyarlari ayarlar = KagitAyarlari();
  KitapSortOrder sortOrder = KitapSortOrder.recent;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _rootDir = testWorkspaceDir ?? await getApplicationDocumentsDirectory();
    _libraryDir = Directory('${_rootDir.path}/library')..createSync(recursive: true);
    _rendersDir = Directory('${_rootDir.path}/renders')..createSync(recursive: true);
    _exportsDir = Directory('${_rootDir.path}/exports')..createSync(recursive: true);

    await _loadState();
    _seedDefaultTeacherData();

    if (enableNativePlatform && items.isEmpty) {
      await _seedStarterDocument();
    }
    if (enableNativePlatform) {
      await checkExternalOpenedPdf();
    }
    notifyListeners();
  }

  Directory get libraryDir => _libraryDir;
  Directory get exportsDir => _exportsDir;

  List<KitaplikOgesi> get activeItems {
    final list = items.where((i) => !i.inTrash).toList();
    list.sort((a, b) {
      switch (sortOrder) {
        case KitapSortOrder.recent:
          final ad = a.lastOpenedAt ?? a.modifiedAt;
          final bd = b.lastOpenedAt ?? b.modifiedAt;
          return bd.compareTo(ad);
        case KitapSortOrder.name:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case KitapSortOrder.size:
          return b.fileSize.compareTo(a.fileSize);
        case KitapSortOrder.pages:
          return b.pageCount.compareTo(a.pageCount);
      }
    });
    return list;
  }

  List<KitaplikOgesi> get starredItems => activeItems.where((i) => i.isStarred).toList();
  List<KitaplikOgesi> get trashItems => items.where((i) => i.inTrash).toList();
  List<KitaplikOgesi> get recentOpenedItems =>
      activeItems.where((i) => i.lastOpenedAt != null).take(6).toList();

  void setSortOrder(KitapSortOrder order) {
    sortOrder = order;
    notifyListeners();
  }

  void recordToolUse(KagitToolId id) {
    recentTools.remove(id);
    recentTools.insert(0, id);
    if (recentTools.length > 6) {
      recentTools = recentTools.take(6).toList();
    }
    _saveStateSync();
    notifyListeners();
  }

  File get _stateFile => File('${_rootDir.path}/kagit_state.json');

  Future<void> _loadState() async {
    try {
      if (!_stateFile.existsSync()) return;
      final raw = jsonDecode(_stateFile.readAsStringSync()) as Map<String, dynamic>;
      items = (raw['items'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(KitaplikOgesi.fromJson)
              .toList() ??
          [];
      folders = (raw['folders'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(Klasor.fromJson)
              .toList() ??
          [];
      final annRaw = raw['annotations'] as Map<String, dynamic>?;
      if (annRaw != null) {
        annotationsByDoc = annRaw.map(
          (k, v) => MapEntry(
            k,
            (v as List?)?.whereType<Map<String, dynamic>>().map(PdfAnnotation.fromJson).toList() ?? [],
          ),
        );
      }
      final sigRaw = raw['signature'] as List?;
      if (sigRaw != null) {
        savedSignatureStrokes = sigRaw
            .whereType<List>()
            .map(
              (stroke) => stroke
                  .whereType<Map<String, dynamic>>()
                  .map(NormPoint.fromJson)
                  .toList(),
            )
            .toList();
      }
      final recentRaw = raw['recentTools'] as List?;
      if (recentRaw != null && recentRaw.isNotEmpty) {
        recentTools = recentRaw
            .whereType<String>()
            .map(
              (name) => KagitToolId.values.firstWhere(
                (t) => t.name == name,
                orElse: () => KagitToolId.goruntuleVeNot,
              ),
            )
            .toList();
      }
      siniflar = (raw['siniflar'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(SinifGrubu.fromJson)
              .toList() ??
          [];
      if (raw['ayarlar'] is Map<String, dynamic>) {
        ayarlar = KagitAyarlari.fromJson(raw['ayarlar'] as Map<String, dynamic>);
      }
      if (raw['aiConfig'] is Map<String, dynamic>) {
        aiService.config = KagitAiConfig.fromJson(raw['aiConfig'] as Map<String, dynamic>);
      }
    } catch (_) {
      // Bozuk durum dosyasında temiz başla.
    }
  }

  void _saveStateSync() {
    try {
      final payload = {
        'items': items.map((e) => e.toJson()).toList(),
        'folders': folders.map((e) => e.toJson()).toList(),
        'annotations': annotationsByDoc.map(
          (k, v) => MapEntry(k, v.map((a) => a.toJson()).toList()),
        ),
        'signature': savedSignatureStrokes
            .map((stroke) => stroke.map((p) => p.toJson()).toList())
            .toList(),
        'recentTools': recentTools.map((e) => e.name).toList(),
        'siniflar': siniflar.map((s) => s.toJson()).toList(),
        'ayarlar': ayarlar.toJson(),
        'aiConfig': aiService.config.toJson(),
      };
      _stateFile.writeAsStringSync(jsonEncode(payload));
    } catch (_) {}
  }

  void persist() {
    _saveStateSync();
    notifyListeners();
  }

  void _seedDefaultTeacherData() {
    if (siniflar.isEmpty) {
      siniflar = [
        SinifGrubu(
          id: _uuid.v4(),
          name: '10-A Sınıfı',
          students: [
            OgrenciKaydi(id: _uuid.v4(), no: '101', adSoyad: 'Zeynep Yılmaz'),
            OgrenciKaydi(id: _uuid.v4(), no: '102', adSoyad: 'Emre Kaya'),
            OgrenciKaydi(id: _uuid.v4(), no: '103', adSoyad: 'Elif Demir'),
            OgrenciKaydi(id: _uuid.v4(), no: '104', adSoyad: 'Kerem Arslan'),
          ],
        ),
      ];
      _saveStateSync();
    }
    if (folders.isEmpty) {
      folders = [
        Klasor(id: _uuid.v4(), name: 'Sınavlar', colorValue: 0xFFD98E26),
        Klasor(id: _uuid.v4(), name: 'Resmî Belgeler', colorValue: 0xFF2F64B8),
        Klasor(id: _uuid.v4(), name: 'Ders Notları', colorValue: 0xFF288557),
      ];
      _saveStateSync();
    }
  }

  Future<void> _seedStarterDocument() async {
    try {
      await createTextOrBlankPdf(
        title: 'Kâğıt Stüdyosu — Hoş Geldiniz & Örnek Sınav',
        subtitle: 'Android İçin Editoryal PDF Atölyesi',
        pattern: BlankPaperPattern.blank,
        body: '''Kâğıt uygulamasının tüm araçlarını bu belge üzerinde hemen deneyebilirsiniz.

1. Öğretmen Stüdyosu ve Sınav Araçları
Sınav kâğıtlarını bölün, A/B kitapçıkları üretin ve sayfaya "Doğru", "Yanlış" veya puan damgaları (+10, +25, -5) yerleştirip tek dokunuşla Excel (.xlsx) puan raporu alın.

2. Cihaz İçi OCR ve Otomatik PII Gizleme
Taranmış belgelerden internetsiz ML Kit motoru ile Türkçe metin çıkarın. Paylaşmadan önce T.C. Kimlik, IBAN ve telefon bilgilerini otomatik siyah şeritle karartın.

Örnek Soru 1: Cumhuriyet Dönemi Türk Edebiyatı'nda hikâye ve roman türünün toplumsal gerçekçilikle kurduğu ilişkiyi 3 cümleyle açıklayınız.

Örnek Soru 2: Aşağıdaki ifadelerden hangisi belge imzalama ve N-up kitapçık basımının kağıt tasarrufuna etkisini doğru açıklar?
A) Sayfaları katlayarak 2 yaprağa 4 sayfa sığdırır.
B) Yalnızca ilk sayfayı yazdırır.
C) PDF metnini siler.
D) Kenarlıkları 4 kat büyütür.''',
      );
    } catch (_) {}
  }

  // ---- Belge CRUD & Klasörleme ----

  String _uniquePath(String fileName) {
    var clean = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (clean.isEmpty) clean = 'belge';
    if (!clean.toLowerCase().endsWith('.pdf')) clean = '$clean.pdf';
    var f = File('${_libraryDir.path}/$clean');
    if (!f.existsSync()) return f.path;
    final stem = clean.substring(0, clean.length - 4);
    int i = 2;
    while (f.existsSync()) {
      f = File('${_libraryDir.path}/${stem}_$i.pdf');
      i++;
    }
    return f.path;
  }

  Future<KitaplikOgesi> registerPdfFile(
    String path, {
    String? customTitle,
    String? folderId,
    List<String> tags = const [],
  }) async {
    int pageCount = 1;
    int fileSize = File(path).existsSync() ? File(path).lengthSync() : 0;
    if (enableNativePlatform) {
      try {
        final info = await getPdfInfo(path);
        pageCount = (info['pageCount'] as num?)?.toInt() ?? 1;
        fileSize = (info['fileSize'] as num?)?.toInt() ?? fileSize;
      } catch (_) {}
    }

    final fileName = File(path).uri.pathSegments.last;
    final stem = fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final item = KitaplikOgesi(
      id: _uuid.v4(),
      title: customTitle?.trim().isNotEmpty == true ? customTitle!.trim() : stem,
      path: path,
      pageCount: pageCount,
      fileSize: fileSize,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
      folderId: folderId,
      tags: tags,
    );
    items.insert(0, item);
    _saveStateSync();
    notifyListeners();
    return item;
  }

  void markOpened(KitaplikOgesi item, {int? pageIndex}) {
    item.lastOpenedAt = DateTime.now();
    if (pageIndex != null) item.lastPage = pageIndex;
    _saveStateSync();
    notifyListeners();
  }

  void toggleStar(KitaplikOgesi item) {
    item.isStarred = !item.isStarred;
    _saveStateSync();
    notifyListeners();
  }

  void renameItem(KitaplikOgesi item, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    item.title = trimmed;
    item.modifiedAt = DateTime.now();
    _saveStateSync();
    notifyListeners();
  }

  void moveToFolder(KitaplikOgesi item, String? folderId) {
    item.folderId = folderId;
    item.modifiedAt = DateTime.now();
    _saveStateSync();
    notifyListeners();
  }

  void moveToTrash(KitaplikOgesi item) {
    item.inTrash = true;
    _saveStateSync();
    notifyListeners();
  }

  void restoreFromTrash(KitaplikOgesi item) {
    item.inTrash = false;
    _saveStateSync();
    notifyListeners();
  }

  void deletePermanently(KitaplikOgesi item) {
    items.removeWhere((i) => i.id == item.id);
    annotationsByDoc.remove(item.id);
    _undoStacks.remove(item.id);
    _redoStacks.remove(item.id);
    try {
      final f = File(item.path);
      if (f.existsSync() && f.path.contains(_rootDir.path)) {
        f.deleteSync();
      }
    } catch (_) {}
    _saveStateSync();
    notifyListeners();
  }

  void emptyTrash() {
    for (final item in trashItems.toList()) {
      deletePermanently(item);
    }
  }

  void createFolder(String name, {int colorValue = 0xFFDB3D33}) {
    final clean = name.trim();
    if (clean.isEmpty) return;
    folders.add(Klasor(id: _uuid.v4(), name: clean, colorValue: colorValue));
    _saveStateSync();
    notifyListeners();
  }

  void deleteFolder(String folderId) {
    folders.removeWhere((f) => f.id == folderId);
    for (final i in items) {
      if (i.folderId == folderId) i.folderId = null;
    }
    _saveStateSync();
    notifyListeners();
  }

  // ---- Anotasyon & Undo / Redo ----

  List<PdfAnnotation> annotationsFor(String docId, [int? pageIndex]) {
    final all = annotationsByDoc[docId] ?? const [];
    if (pageIndex == null) return all;
    return all.where((a) => a.pageIndex == pageIndex).toList();
  }

  void _pushUndo(String docId) {
    final snapshot = (annotationsByDoc[docId] ?? const [])
        .map((a) => PdfAnnotation.fromJson(a.toJson()))
        .toList();
    _undoStacks.putIfAbsent(docId, () => []).add(snapshot);
    _redoStacks[docId]?.clear();
  }

  bool canUndo(String docId) => (_undoStacks[docId]?.isNotEmpty ?? false);
  bool canRedo(String docId) => (_redoStacks[docId]?.isNotEmpty ?? false);

  void addAnnotation(String docId, PdfAnnotation ann) {
    _pushUndo(docId);
    annotationsByDoc.putIfAbsent(docId, () => []).add(ann);
    _saveStateSync();
    notifyListeners();
  }

  void undoAnnotation(String docId) {
    final stack = _undoStacks[docId];
    if (stack == null || stack.isEmpty) return;
    final current = (annotationsByDoc[docId] ?? const [])
        .map((a) => PdfAnnotation.fromJson(a.toJson()))
        .toList();
    _redoStacks.putIfAbsent(docId, () => []).add(current);
    annotationsByDoc[docId] = stack.removeLast();
    _saveStateSync();
    notifyListeners();
  }

  void redoAnnotation(String docId) {
    final stack = _redoStacks[docId];
    if (stack == null || stack.isEmpty) return;
    final current = (annotationsByDoc[docId] ?? const [])
        .map((a) => PdfAnnotation.fromJson(a.toJson()))
        .toList();
    _undoStacks.putIfAbsent(docId, () => []).add(current);
    annotationsByDoc[docId] = stack.removeLast();
    _saveStateSync();
    notifyListeners();
  }

  void clearPageAnnotations(String docId, int pageIndex) {
    _pushUndo(docId);
    annotationsByDoc[docId]?.removeWhere((a) => a.pageIndex == pageIndex);
    _saveStateSync();
    notifyListeners();
  }

  void saveSignature(List<List<NormPoint>> strokes) {
    savedSignatureStrokes = strokes;
    _saveStateSync();
    notifyListeners();
  }

  // ---- Öğretmen Sınıf Yönetimi ----

  void addClassGroup(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return;
    siniflar.add(SinifGrubu(id: _uuid.v4(), name: clean));
    _saveStateSync();
    notifyListeners();
  }

  void deleteClassGroup(String id) {
    siniflar.removeWhere((s) => s.id == id);
    _saveStateSync();
    notifyListeners();
  }

  void addStudent(String classId, String no, String adSoyad) {
    final idx = siniflar.indexWhere((s) => s.id == classId);
    if (idx < 0) return;
    siniflar[idx].students = [
      ...siniflar[idx].students,
      OgrenciKaydi(id: _uuid.v4(), no: no.trim(), adSoyad: adSoyad.trim()),
    ];
    _saveStateSync();
    notifyListeners();
  }

  void removeStudent(String classId, String studentId) {
    final idx = siniflar.indexWhere((s) => s.id == classId);
    if (idx < 0) return;
    siniflar[idx].students = siniflar[idx].students.where((st) => st.id != studentId).toList();
    _saveStateSync();
    notifyListeners();
  }

  // ---- Yerel PDF / Kamera / OCR / Dışa Aktarım Köprüsü ----

  Future<void> checkExternalOpenedPdf() async {
    if (!enableNativePlatform) return;
    try {
      final path = await _channel.invokeMethod<String>('consumeOpenedFile');
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        await registerPdfFile(path, tags: const ['Dışarıdan']);
      }
    } catch (_) {}
  }

  Future<List<KitaplikOgesi>> importPdfsFromDevice({bool allowMultiple = true, String? folderId}) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'pickFiles',
      {
        'mimeTypes': ['application/pdf'],
        'allowMultiple': allowMultiple,
      },
    );
    if (raw == null || raw.isEmpty) return [];
    final added = <KitaplikOgesi>[];
    for (final entry in raw.whereType<Map>()) {
      final srcPath = entry['path'] as String?;
      final name = entry['name'] as String? ?? 'Belge.pdf';
      if (srcPath == null || !File(srcPath).existsSync()) continue;
      final dest = _uniquePath(name);
      File(srcPath).copySync(dest);
      added.add(await registerPdfFile(dest, customTitle: name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''), folderId: folderId));
    }
    return added;
  }

  Future<List<String>> pickImagesFromDevice({bool allowMultiple = true}) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'pickFiles',
      {
        'mimeTypes': ['image/*'],
        'allowMultiple': allowMultiple,
      },
    );
    if (raw == null) return [];
    return raw.whereType<Map>().map((m) => m['path'] as String?).whereType<String>().toList();
  }

  Future<String?> captureCameraPhoto() => _channel.invokeMethod<String>('capturePhoto');

  Future<bool> saveFileToUserLocation(String srcPath, String suggestedName, String mimeType) async {
    final ok = await _channel.invokeMethod<bool>('saveFileAs', {
      'srcPath': srcPath,
      'suggestedName': suggestedName,
      'mimeType': mimeType,
    });
    return ok ?? false;
  }

  Future<void> shareFile(String path, {String title = 'Belge Paylaş', String mimeType = 'application/pdf'}) async {
    await _channel.invokeMethod('shareFile', {
      'path': path,
      'title': title,
      'mimeType': mimeType,
    });
  }

  Future<Map<String, dynamic>> getPdfInfo(String path) async {
    final res = await _channel.invokeMethod<Map>('getPdfInfo', {'path': path});
    return Map<String, dynamic>.from(res ?? {});
  }

  Future<String> renderPdfPage(
    KitaplikOgesi item,
    int pageIndex, {
    int maxWidth = 1100,
    bool trimMargins = false,
  }) async {
    final sig = '${item.id}_${item.modifiedAt.millisecondsSinceEpoch}_${pageIndex}_${maxWidth}_$trimMargins';
    final outPath = '${_rendersDir.path}/$sig.png';
    final outFile = File(outPath);
    if (outFile.existsSync() && outFile.lengthSync() > 100) {
      return outPath;
    }
    await _channel.invokeMethod('renderPage', {
      'path': item.path,
      'pageIndex': pageIndex,
      'maxWidth': maxWidth,
      'outPath': outPath,
      'trimMargins': trimMargins,
    });
    return outPath;
  }

  Future<Map<String, dynamic>> runOcrOnPdf(
    KitaplikOgesi item, {
    List<int>? pageIndices,
    double scale = 2.1,
  }) async {
    final res = await _channel.invokeMethod<Map>('runOcrOnPdf', {
      'path': item.path,
      'pageIndices': pageIndices,
      'scale': scale,
    });
    final map = Map<String, dynamic>.from(res ?? {});
    final fullText = map['fullText'] as String? ?? '';
    if (pageIndices == null && fullText.isNotEmpty) {
      item.cachedOcrText = fullText;
      _saveStateSync();
      notifyListeners();
    }
    return map;
  }

  Future<String> ensureTextExtracted(KitaplikOgesi item) async {
    if (item.cachedOcrText != null && item.cachedOcrText!.trim().isNotEmpty) {
      return item.cachedOcrText!;
    }
    final ocr = await runOcrOnPdf(item);
    return ocr['fullText'] as String? ?? '';
  }

  Future<KitaplikOgesi> createImagesPdf({
    required List<String> imagePaths,
    required String title,
    String filter = 'normal',
    String pageSize = 'a4',
    String? folderId,
  }) async {
    final outPath = _uniquePath(title);
    await _channel.invokeMethod('imagesToPdf', {
      'imagePaths': imagePaths,
      'outPath': outPath,
      'filter': filter,
      'pageSize': pageSize,
    });
    return registerPdfFile(outPath, customTitle: title, folderId: folderId, tags: const ['Tarama']);
  }

  Future<KitaplikOgesi> createTextOrBlankPdf({
    required String title,
    String subtitle = '',
    BlankPaperPattern pattern = BlankPaperPattern.blank,
    String body = '',
    int pageCount = 1,
    OkulBasligi? schoolHeader,
    String? folderId,
  }) async {
    final outPath = _uniquePath(title);
    await _channel.invokeMethod('buildTextPdf', {
      'outPath': outPath,
      'title': title,
      'subtitle': subtitle,
      'pattern': pattern.name,
      'body': body,
      'pageCount': pageCount,
      if (schoolHeader != null)
        'schoolHeader': {...schoolHeader.toJson(), 'enabled': true},
    });
    return registerPdfFile(outPath, customTitle: title, folderId: folderId);
  }

  Future<KitaplikOgesi> mergeDocuments(List<KitaplikOgesi> docs, {String title = 'Birleştirilmiş Belge'}) async {
    final outPath = _uniquePath(title);
    await _channel.invokeMethod('mergePdfs', {
      'paths': docs.map((d) => d.path).toList(),
      'outPath': outPath,
    });
    return registerPdfFile(outPath, customTitle: title, tags: const ['Birleşik']);
  }

  Future<KitaplikOgesi> assembleDocument({
    required String newTitle,
    String? sourcePath,
    List<Map<String, dynamic>>? pageEntries,
    String pageSize = 'original',
    int nUp = 1,
    bool booklet = false,
    bool trimMargins = false,
    int dpi = 150,
    Map<String, dynamic>? watermark,
    Map<String, dynamic>? pageNumbers,
    Map<String, dynamic>? headerFooter,
    Map<String, dynamic>? schoolHeader,
    Map<String, List<Map<String, dynamic>>>? annotationsByPage,
    String? folderId,
    List<String> tags = const [],
  }) async {
    final outPath = _uniquePath(newTitle);
    await _channel.invokeMethod('assemblePdf', {
      'outPath': outPath,
      'path': ?sourcePath,
      'pageEntries': ?pageEntries,
      'pageSize': pageSize,
      'nUp': nUp,
      'booklet': booklet,
      'trimMargins': trimMargins,
      'dpi': dpi,
      'watermark': ?watermark,
      'pageNumbers': ?pageNumbers,
      'headerFooter': ?headerFooter,
      'schoolHeader': ?schoolHeader,
      'annotationsByPage': ?annotationsByPage,
    });
    return registerPdfFile(outPath, customTitle: newTitle, folderId: folderId, tags: tags);
  }

  Future<KitaplikOgesi> flattenAnnotationsToPdf(KitaplikOgesi item, {String? customTitle}) async {
    final anns = annotationsFor(item.id);
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final a in anns) {
      grouped.putIfAbsent(a.pageIndex.toString(), () => []).add(a.toJson());
    }
    return assembleDocument(
      newTitle: customTitle ?? '${item.title} (İşaretli)',
      sourcePath: item.path,
      annotationsByPage: grouped,
      folderId: item.folderId,
      tags: [...item.tags, 'İşaretli'],
    );
  }

  Future<String> writeExportBytes(String fileName, List<int> bytes) async {
    final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${_exportsDir.path}/$safe');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
