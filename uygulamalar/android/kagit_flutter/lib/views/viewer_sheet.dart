import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../kagit_models.dart';
import '../kagit_store.dart';
import '../theme_kagit.dart';
import 'shared_kagit_widgets.dart';

enum ViewerMode {
  gezin,
  kalem,
  vurgula,
  metin,
  imza,
  karart,
  ogretmenPuan,
}

class BelgeEkrani extends StatefulWidget {
  const BelgeEkrani({
    super.key,
    required this.controller,
    required this.item,
    required this.onRunTool,
    this.initialMode = ViewerMode.gezin,
  });

  final KagitController controller;
  final KitaplikOgesi item;
  final void Function(KagitTool tool, KitaplikOgesi doc) onRunTool;
  final ViewerMode initialMode;

  @override
  State<BelgeEkrani> createState() => _BelgeEkraniState();
}

class _BelgeEkraniState extends State<BelgeEkrani> {
  static const Uuid _uuid = Uuid();

  late int _currentPage;
  late ViewerMode _mode;
  late ReadingTint _tint;
  Color _activeColor = KagitTema.vurgu;
  double _strokeWidth = 0.005;

  final Map<int, String> _renderedPaths = {};
  final Map<int, bool> _loadingPages = {};
  final Map<int, double> _pageAspects = {};

  List<NormPoint> _activeStroke = [];
  Offset? _redactStart;
  Offset? _redactCurrent;

  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  List<int> _searchMatchedPages = [];
  bool _ocrRunning = false;
  bool _flattening = false;
  String _selectedTeacherStamp = '+10';
  Size _lastCanvasSize = const Size(400, 560);

  static const List<String> _teacherStamps = [
    '+10',
    '+5',
    '+20',
    '+25',
    '-5',
    'Doğru ✓',
    'Yanlış ✗',
    'Aferin!',
  ];

  static const List<Color> _inkColors = [
    KagitTema.vurgu,
    Color(0xFF1A1917),
    Color(0xFF2F64B8),
    Color(0xFF288557),
    Color(0xFFD98E26),
    Color(0xFF7B4EC2),
  ];

  @override
  void initState() {
    super.initState();
    _currentPage = widget.item.lastPage.clamp(0, (widget.item.pageCount - 1).clamp(0, 9999));
    _mode = widget.initialMode;
    _tint = widget.controller.ayarlar.readingTint;
    widget.controller.addListener(_onStoreChanged);
    _loadMetadataAndCurrentPage();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStoreChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMetadataAndCurrentPage() async {
    widget.controller.markOpened(widget.item, pageIndex: _currentPage);
    if (widget.controller.enableNativePlatform) {
      try {
        final info = await widget.controller.getPdfInfo(widget.item.path);
        final pages = info['pages'] as List?;
        if (pages != null) {
          for (final p in pages.whereType<Map>()) {
            final idx = (p['index'] as num?)?.toInt() ?? 0;
            final w = (p['width'] as num?)?.toDouble() ?? 595;
            final h = (p['height'] as num?)?.toDouble() ?? 842;
            _pageAspects[idx] = w / (h <= 0 ? 1 : h);
          }
        }
      } catch (_) {}
      await _ensurePageRendered(_currentPage);
      if (_currentPage + 1 < widget.item.pageCount) {
        _ensurePageRendered(_currentPage + 1);
      }
    }
  }

  Future<void> _ensurePageRendered(int idx) async {
    if (!widget.controller.enableNativePlatform) return;
    if (_renderedPaths.containsKey(idx) || _loadingPages[idx] == true) return;
    _loadingPages[idx] = true;
    try {
      final path = await widget.controller.renderPdfPage(widget.item, idx, maxWidth: 1280);
      if (mounted) {
        setState(() => _renderedPaths[idx] = path);
      }
    } catch (_) {
    } finally {
      _loadingPages[idx] = false;
    }
  }

  void _goToPage(int idx) {
    final bounded = idx.clamp(0, (widget.item.pageCount - 1).clamp(0, 9999));
    setState(() => _currentPage = bounded);
    widget.controller.markOpened(widget.item, pageIndex: bounded);
    _ensurePageRendered(bounded);
    if (bounded + 1 < widget.item.pageCount) _ensurePageRendered(bounded + 1);
    if (bounded - 1 >= 0) _ensurePageRendered(bounded - 1);
  }

  ColorFilter? get _readingColorFilter {
    switch (_tint) {
      case ReadingTint.normal:
        return null;
      case ReadingTint.sepia:
        return const ColorFilter.matrix([
          0.95, 0.0, 0.0, 0, 10,
          0.0, 0.89, 0.0, 0, 6,
          0.0, 0.0, 0.74, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case ReadingTint.night:
        return const ColorFilter.matrix([
          -0.9, 0, 0, 0, 240,
          0, -0.9, 0, 0, 236,
          0, 0, -0.9, 0, 228,
          0, 0, 0, 1, 0,
        ]);
    }
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _searchMatchedPages = []);
      return;
    }
    String text = widget.item.cachedOcrText ?? '';
    if (text.trim().isEmpty && widget.controller.enableNativePlatform) {
      setState(() => _ocrRunning = true);
      try {
        text = await widget.controller.ensureTextExtracted(widget.item);
      } catch (e) {
        if (mounted) showKagitSnack(context, 'OCR araması hatası: $e', isError: true);
      } finally {
        if (mounted) setState(() => _ocrRunning = false);
      }
    }
    final hits = <int>[];
    final sections = text.split('--- Sayfa ');
    for (final sec in sections) {
      final nl = sec.indexOf('\n');
      if (nl < 0) continue;
      final numStr = sec.substring(0, nl).replaceAll(RegExp(r'[^0-9]'), '');
      final pNo = int.tryParse(numStr);
      if (pNo != null && sec.toLowerCase().contains(q)) {
        hits.add(pNo - 1);
      }
    }
    setState(() => _searchMatchedPages = hits);
    if (hits.isNotEmpty) {
      _goToPage(hits.first);
    } else if (mounted) {
      showKagitSnack(context, '"$query" belgede bulunamadı.');
    }
  }

  Future<void> _openSignaturePadOrPlace() async {
    if (widget.controller.savedSignatureStrokes.isNotEmpty) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.draw_rounded, color: KagitTema.vurgu),
                title: const Text('Kayıtlı İmzamı Sayfaya Yerleştir'),
                subtitle: const Text('Alt orta alana ekler; yerini araçlarla düzenleyebilirsiniz'),
                onTap: () => Navigator.pop(ctx, 'use'),
              ),
              ListTile(
                leading: const Icon(Icons.create_rounded),
                title: const Text('Yeni El Yazısı İmza Çiz'),
                onTap: () => Navigator.pop(ctx, 'draw'),
              ),
            ],
          ),
        ),
      );
      if (choice == 'use') {
        _stampSavedSignatureOnPage();
        return;
      }
      if (choice != 'draw') return;
    }

    if (!mounted) return;
    final strokes = await showDialog<List<List<NormPoint>>>(
      context: context,
      builder: (_) => const _SignaturePadDialog(),
    );
    if (strokes != null && strokes.isNotEmpty) {
      widget.controller.saveSignature(strokes);
      _stampSavedSignatureOnPage();
    }
  }

  void _stampSavedSignatureOnPage() {
    for (final stroke in widget.controller.savedSignatureStrokes) {
      final mapped = stroke
          .map((p) => NormPoint(0.58 + p.x * 0.30, 0.78 + p.y * 0.10))
          .toList();
      widget.controller.addAnnotation(
        widget.item.id,
        PdfAnnotation(
          id: _uuid.v4(),
          pageIndex: _currentPage,
          kind: AnnotationKind.signature,
          colorValue: const Color(0xFF15326E).toARGB32(),
          strokeWidth: 0.0045,
          points: mapped,
        ),
      );
    }
    showKagitSnack(context, 'İmza ${widget.item.title} (Sayfa ${_currentPage + 1}) üzerine eklendi.');
  }

  Future<void> _flattenAndSave() async {
    if (_flattening) return;
    setState(() => _flattening = true);
    try {
      final flattened = await widget.controller.flattenAnnotationsToPdf(widget.item);
      if (!mounted) return;
      showKagitSnack(context, 'İşaretler yeni PDF dosyasına yakıldı: ${flattened.title}');
    } catch (e) {
      if (mounted) showKagitSnack(context, 'Kaydedilemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _flattening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.item;
    final pageAnns = widget.controller.annotationsFor(doc.id, _currentPage);
    final totalPuan = _sumDocPoints();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'OCR metninde ara...',
                  border: InputBorder.none,
                  suffixIcon: _ocrRunning
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.search_rounded),
                          onPressed: () => _runSearch(_searchCtrl.text),
                        ),
                ),
                onSubmitted: _runSearch,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kagitSerif(context, size: 16.5),
                  ),
                  Text(
                    'Sayfa ${_currentPage + 1} / ${doc.pageCount}'
                    '${totalPuan != 0 ? "  •  Toplam Puan: ${totalPuan.toStringAsFixed(totalPuan % 1 == 0 ? 0 : 1)}" : ""}',
                    style: TextStyle(fontSize: 11.5, color: KagitTema.inkSecondary(context)),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: _isSearching ? 'Aramayı Kapat' : 'Belgede Ara',
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) _searchMatchedPages = [];
            }),
          ),
          IconButton(
            tooltip: 'Geri Al',
            icon: const Icon(Icons.undo_rounded),
            onPressed: widget.controller.canUndo(doc.id)
                ? () => widget.controller.undoAnnotation(doc.id)
                : null,
          ),
          IconButton(
            tooltip: 'İleri Al',
            icon: const Icon(Icons.redo_rounded),
            onPressed: widget.controller.canRedo(doc.id)
                ? () => widget.controller.redoAnnotation(doc.id)
                : null,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'flatten':
                  await _flattenAndSave();
                case 'ai_summary':
                  final t = kagitToolsCatalog.firstWhere((e) => e.id == KagitToolId.aiOzetle);
                  widget.onRunTool(t, doc);
                case 'ai_chat':
                  final t = kagitToolsCatalog.firstWhere((e) => e.id == KagitToolId.aiSohbet);
                  widget.onRunTool(t, doc);
                case 'ocr':
                  final t = kagitToolsCatalog.firstWhere((e) => e.id == KagitToolId.ocrMetinTanima);
                  widget.onRunTool(t, doc);
                case 'redact':
                  final t = kagitToolsCatalog.firstWhere((e) => e.id == KagitToolId.piiKarartma);
                  widget.onRunTool(t, doc);
                case 'clear_page':
                  widget.controller.clearPageAnnotations(doc.id, _currentPage);
                case 'share':
                  await widget.controller.shareFile(doc.path, title: doc.title);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'flatten', child: Text('Notları PDF’e Yak ve Kaydet')),
              PopupMenuItem(value: 'ocr', child: Text('OCR Metin Çıkar')),
              PopupMenuItem(value: 'redact', child: Text('Otomatik PII Karartma')),
              PopupMenuItem(value: 'ai_summary', child: Text('Yapay Zekâ ile Özetle')),
              PopupMenuItem(value: 'ai_chat', child: Text('Belgeye Soru Sor (AI)')),
              PopupMenuItem(value: 'clear_page', child: Text('Bu Sayfanın İşaretlerini Temizle')),
              PopupMenuItem(value: 'share', child: Text('Paylaş')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTopReadingStrip(),
          if (_searchMatchedPages.isNotEmpty)
            Container(
              color: KagitTema.altinMuhur.withValues(alpha: 0.14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text('Eşleşen Sayfalar: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    for (final p in _searchMatchedPages)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text('S.${p + 1}', style: const TextStyle(fontSize: 11.5)),
                          onPressed: () => _goToPage(p),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Container(
              color: _tint == ReadingTint.night
                  ? const Color(0xFF0E0D0C)
                  : KagitTema.softBg(context),
              child: InteractiveViewer(
                panEnabled: _mode == ViewerMode.gezin,
                scaleEnabled: _mode == ViewerMode.gezin,
                minScale: 0.9,
                maxScale: 4.5,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildPageCanvas(pageAnns),
                  ),
                ),
              ),
            ),
          ),
          _buildThumbnailStrip(),
          _buildBottomToolDock(),
        ],
      ),
    );
  }

  Widget _buildTopReadingStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: KagitTema.cardBg(context),
        border: Border(bottom: BorderSide(color: KagitTema.border(context))),
      ),
      child: Row(
        children: [
          SegmentedButton<ReadingTint>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            segments: const [
              ButtonSegment(value: ReadingTint.normal, label: Text('Normal')),
              ButtonSegment(value: ReadingTint.sepia, label: Text('Sepya')),
              ButtonSegment(value: ReadingTint.night, label: Text('Gece')),
            ],
            selected: {_tint},
            onSelectionChanged: (set) {
              setState(() => _tint = set.first);
              widget.controller.ayarlar.readingTint = _tint;
              widget.controller.persist();
            },
          ),
          const Spacer(),
          if (_flattening)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            FilledButton.tonalIcon(
              onPressed: _flattenAndSave,
              icon: const Icon(Icons.save_alt_rounded, size: 17),
              label: const Text('Kaydet', style: TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Widget _buildPageCanvas(List<PdfAnnotation> pageAnns) {
    final aspect = _pageAspects[_currentPage] ?? (595 / 842);
    final rendered = _renderedPaths[_currentPage];

    return AspectRatio(
      aspectRatio: aspect,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          _lastCanvasSize = size;
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _handleCanvasTap(d.localPosition, size),
                onPanStart: (d) => _handlePanStart(d.localPosition, size),
                onPanUpdate: (d) => _handlePanUpdate(d.localPosition, size),
                onPanEnd: (_) => _handlePanEnd(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (rendered != null && File(rendered).existsSync())
                      ColorFiltered(
                        colorFilter: _readingColorFilter ?? const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                        child: Image.file(
                          File(rendered),
                          key: ValueKey(rendered),
                          fit: BoxFit.fill,
                        ),
                      )
                    else
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.description_outlined, size: 42, color: KagitTema.vurgu),
                            const SizedBox(height: 8),
                            Text(
                              'Sayfa ${_currentPage + 1}',
                              style: kagitSerif(context, size: 17, color: Colors.black87),
                            ),
                            if (widget.controller.enableNativePlatform)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                          ],
                        ),
                      ),
                    CustomPaint(
                      painter: _AnnotationCanvasPainter(
                        annotations: pageAnns,
                        activeStroke: _activeStroke,
                        activeMode: _mode,
                        activeColor: _activeColor,
                        activeStrokeWidth: _strokeWidth,
                        redactStart: _redactStart,
                        redactCurrent: _redactCurrent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  NormPoint _norm(Offset p, Size size) => NormPoint(
        (p.dx / size.width).clamp(0.0, 1.0),
        (p.dy / size.height).clamp(0.0, 1.0),
      );

  Future<void> _handleCanvasTap(Offset pos, Size size) async {
    final n = _norm(pos, size);
    if (_mode == ViewerMode.metin) {
      final ctrl = TextEditingController();
      final text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Metin Notu Ekle'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Açıklama veya düzeltme notu yazın...'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Ekle')),
          ],
        ),
      );
      ctrl.dispose();
      if (text != null && text.trim().isNotEmpty) {
        widget.controller.addAnnotation(
          widget.item.id,
          PdfAnnotation(
            id: _uuid.v4(),
            pageIndex: _currentPage,
            kind: AnnotationKind.text,
            colorValue: _activeColor.toARGB32(),
            x: n.x,
            y: n.y,
            text: text.trim(),
          ),
        );
      }
    } else if (_mode == ViewerMode.ogretmenPuan) {
      final isPuan = RegExp(r'^[+\-]\d+').hasMatch(_selectedTeacherStamp);
      widget.controller.addAnnotation(
        widget.item.id,
        PdfAnnotation(
          id: _uuid.v4(),
          pageIndex: _currentPage,
          kind: isPuan ? AnnotationKind.puan : AnnotationKind.stamp,
          colorValue: _selectedTeacherStamp.contains('✗') || _selectedTeacherStamp.startsWith('-')
              ? KagitTema.vurgu.toARGB32()
              : KagitTema.yaprakYesili.toARGB32(),
          x: n.x,
          y: n.y,
          text: _selectedTeacherStamp,
        ),
      );
    } else if (_mode == ViewerMode.imza) {
      await _openSignaturePadOrPlace();
    }
  }

  void _handlePanStart(Offset pos, Size size) {
    if (_mode == ViewerMode.kalem || _mode == ViewerMode.vurgula) {
      setState(() => _activeStroke = [_norm(pos, size)]);
    } else if (_mode == ViewerMode.karart) {
      setState(() {
        _redactStart = pos;
        _redactCurrent = pos;
      });
    }
  }

  void _handlePanUpdate(Offset pos, Size size) {
    if (_mode == ViewerMode.kalem || _mode == ViewerMode.vurgula) {
      setState(() => _activeStroke = [..._activeStroke, _norm(pos, size)]);
    } else if (_mode == ViewerMode.karart) {
      setState(() => _redactCurrent = pos);
    }
  }

  void _handlePanEnd() {
    if ((_mode == ViewerMode.kalem || _mode == ViewerMode.vurgula) && _activeStroke.length >= 2) {
      widget.controller.addAnnotation(
        widget.item.id,
        PdfAnnotation(
          id: _uuid.v4(),
          pageIndex: _currentPage,
          kind: _mode == ViewerMode.vurgula ? AnnotationKind.highlight : AnnotationKind.ink,
          colorValue: (_mode == ViewerMode.vurgula ? const Color(0xFFFFD500) : _activeColor).toARGB32(),
          strokeWidth: _mode == ViewerMode.vurgula ? 0.022 : _strokeWidth,
          points: _activeStroke,
        ),
      );
      setState(() => _activeStroke = []);
    } else if (_mode == ViewerMode.karart && _redactStart != null && _redactCurrent != null) {
      final r = Rect.fromPoints(_redactStart!, _redactCurrent!);
      if (r.width > 6 && r.height > 6 && _lastCanvasSize.width > 10 && _lastCanvasSize.height > 10) {
        widget.controller.addAnnotation(
          widget.item.id,
          PdfAnnotation(
            id: _uuid.v4(),
            pageIndex: _currentPage,
            kind: AnnotationKind.redact,
            colorValue: 0xFF000000,
            x: (r.left / _lastCanvasSize.width).clamp(0.0, 1.0),
            y: (r.top / _lastCanvasSize.height).clamp(0.0, 1.0),
            w: (r.width / _lastCanvasSize.width).clamp(0.02, 1.0),
            h: (r.height / _lastCanvasSize.height).clamp(0.01, 1.0),
          ),
        );
      }
      setState(() {
        _redactStart = null;
        _redactCurrent = null;
      });
    }
    _activeStroke = [];
  }

  Widget _buildThumbnailStrip() {
    if (widget.item.pageCount <= 1) return const SizedBox.shrink();
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: KagitTema.cardBg(context),
        border: Border(top: BorderSide(color: KagitTema.border(context))),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        itemCount: widget.item.pageCount,
        itemBuilder: (_, idx) {
          final active = idx == _currentPage;
          final annLen = widget.controller.annotationsFor(widget.item.id, idx).length;
          return GestureDetector(
            onTap: () => _goToPage(idx),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: active ? KagitTema.vurgu : KagitTema.softBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? KagitTema.vurgu : KagitTema.border(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${idx + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: active ? Colors.white : KagitTema.inkPrimary(context),
                    ),
                  ),
                  if (annLen > 0) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.circle,
                      size: 6,
                      color: active ? Colors.white : KagitTema.vurgu,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomToolDock() {
    return Container(
      decoration: BoxDecoration(
        color: KagitTema.cardBg(context),
        border: Border(top: BorderSide(color: KagitTema.border(context))),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_mode == ViewerMode.kalem)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in _inkColors)
                      GestureDetector(
                        onTap: () => setState(() => _activeColor = c),
                        child: Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _activeColor == c ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: _activeColor == c
                                ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)]
                                : null,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    SegmentedButton<double>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: 0.003, label: Text('İnce', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 0.006, label: Text('Orta', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 0.011, label: Text('Kalın', style: TextStyle(fontSize: 11))),
                      ],
                      selected: {_strokeWidth},
                      onSelectionChanged: (s) => setState(() => _strokeWidth = s.first),
                    ),
                  ],
                ),
              ),
            if (_mode == ViewerMode.ogretmenPuan)
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  itemCount: _teacherStamps.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final st = _teacherStamps[i];
                    final sel = st == _selectedTeacherStamp;
                    return ChoiceChip(
                      label: Text(st, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      selected: sel,
                      onSelected: (_) => setState(() => _selectedTeacherStamp = st),
                    );
                  },
                ),
              ),
            if (_mode == ViewerMode.karart)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Sayfada gizlemek istediğiniz bölgenin üzerine dokunup PII karartma aracını veya serbest silgiyi kullanın.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: KagitTema.inkSecondary(context)),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _dockButton(ViewerMode.gezin, Icons.pan_tool_alt_rounded, 'Gezin'),
                  _dockButton(ViewerMode.kalem, Icons.edit_rounded, 'Kalem'),
                  _dockButton(ViewerMode.vurgula, Icons.highlight_rounded, 'Vurgula'),
                  _dockButton(ViewerMode.metin, Icons.title_rounded, 'Metin'),
                  _dockButton(ViewerMode.imza, Icons.draw_rounded, 'İmza'),
                  _dockButton(ViewerMode.karart, Icons.visibility_off_rounded, 'Karart'),
                  _dockButton(ViewerMode.ogretmenPuan, Icons.verified_rounded, 'Puan / Damga'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dockButton(ViewerMode mode, IconData icon, String label) {
    final active = _mode == mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _mode = mode);
          if (mode == ViewerMode.imza) {
            _openSignaturePadOrPlace();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? KagitTema.vurgu : KagitTema.softBg(context),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: active ? Colors.white : KagitTema.inkPrimary(context)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : KagitTema.inkPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _sumDocPoints() {
    double sum = 0;
    for (final a in widget.controller.annotationsFor(widget.item.id)) {
      if (a.kind != AnnotationKind.puan) continue;
      final m = RegExp(r'([+\-]?\d+(?:[.,]\d+)?)').firstMatch(a.text.replaceAll(',', '.'));
      if (m != null) sum += double.tryParse(m.group(1)!) ?? 0;
    }
    return sum;
  }
}

class _AnnotationCanvasPainter extends CustomPainter {
  const _AnnotationCanvasPainter({
    required this.annotations,
    required this.activeStroke,
    required this.activeMode,
    required this.activeColor,
    required this.activeStrokeWidth,
    this.redactStart,
    this.redactCurrent,
  });

  final List<PdfAnnotation> annotations;
  final List<NormPoint> activeStroke;
  final ViewerMode activeMode;
  final Color activeColor;
  final double activeStrokeWidth;
  final Offset? redactStart;
  final Offset? redactCurrent;

  @override
  void paint(Canvas canvas, Size size) {
    for (final ann in annotations) {
      switch (ann.kind) {
        case AnnotationKind.ink:
        case AnnotationKind.highlight:
        case AnnotationKind.signature:
          if (ann.points.length < 2) continue;
          final path = Path()..moveTo(ann.points.first.x * size.width, ann.points.first.y * size.height);
          for (int i = 1; i < ann.points.length; i++) {
            path.lineTo(ann.points[i].x * size.width, ann.points[i].y * size.height);
          }
          final c = Color(ann.colorValue);
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = (ann.strokeWidth * size.width).clamp(1.5, 24.0)
            ..color = ann.kind == AnnotationKind.highlight ? c.withValues(alpha: 0.36) : c;
          canvas.drawPath(path, paint);

        case AnnotationKind.redact:
          final rect = Rect.fromLTWH(
            ann.x * size.width,
            ann.y * size.height,
            ann.w * size.width,
            ann.h * size.height,
          );
          canvas.drawRect(rect, Paint()..color = Colors.black);

        case AnnotationKind.text:
        case AnnotationKind.stamp:
        case AnnotationKind.puan:
          final tp = TextPainter(
            text: TextSpan(
              text: ann.text,
              style: TextStyle(
                color: Color(ann.colorValue),
                fontSize: (ann.fontSize * size.width).clamp(11, 32),
                fontWeight: FontWeight.w700,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final pos = Offset(ann.x * size.width, ann.y * size.height);
          if (ann.kind == AnnotationKind.stamp || ann.kind == AnnotationKind.puan) {
            final box = Rect.fromLTWH(pos.dx - 6, pos.dy - 4, tp.width + 12, tp.height + 8);
            final rrect = RRect.fromRectAndRadius(box, const Radius.circular(6));
            canvas.drawRRect(rrect, Paint()..color = Color(ann.colorValue).withValues(alpha: 0.14));
            canvas.drawRRect(
              rrect,
              Paint()
                ..color = Color(ann.colorValue)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.6,
            );
          }
          tp.paint(canvas, pos);
      }
    }

    if (activeStroke.length >= 2) {
      final path = Path()..moveTo(activeStroke.first.x * size.width, activeStroke.first.y * size.height);
      for (int i = 1; i < activeStroke.length; i++) {
        path.lineTo(activeStroke[i].x * size.width, activeStroke[i].y * size.height);
      }
      final isHigh = activeMode == ViewerMode.vurgula;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = ((isHigh ? 0.022 : activeStrokeWidth) * size.width).clamp(1.5, 24.0)
        ..color = isHigh ? const Color(0xFFFFD500).withValues(alpha: 0.4) : activeColor;
      canvas.drawPath(path, paint);
    }

    if (redactStart != null && redactCurrent != null) {
      canvas.drawRect(Rect.fromPoints(redactStart!, redactCurrent!), Paint()..color = Colors.black54);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationCanvasPainter old) => true;
}

class _SignaturePadDialog extends StatefulWidget {
  const _SignaturePadDialog();

  @override
  State<_SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<_SignaturePadDialog> {
  final List<List<NormPoint>> _strokes = [];
  List<NormPoint> _current = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('El Yazısı İmzanızı Çizin'),
      content: SizedBox(
        width: 320,
        height: 170,
        child: LayoutBuilder(
          builder: (_, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: KagitTema.border(context)),
              ),
              child: GestureDetector(
                onPanStart: (d) {
                  setState(() {
                    _current = [
                      NormPoint(
                        (d.localPosition.dx / size.width).clamp(0, 1),
                        (d.localPosition.dy / size.height).clamp(0, 1),
                      ),
                    ];
                  });
                },
                onPanUpdate: (d) {
                  setState(() {
                    _current = [
                      ..._current,
                      NormPoint(
                        (d.localPosition.dx / size.width).clamp(0, 1),
                        (d.localPosition.dy / size.height).clamp(0, 1),
                      ),
                    ];
                  });
                },
                onPanEnd: (_) {
                  if (_current.length >= 2) {
                    setState(() {
                      _strokes.add(_current);
                      _current = [];
                    });
                  }
                },
                child: CustomPaint(
                  painter: _SigPainter(strokes: _strokes, current: _current),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _strokes.clear();
            _current = [];
          }),
          child: const Text('Temizle'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        FilledButton(
          onPressed: _strokes.isEmpty ? null : () => Navigator.pop(context, _strokes),
          child: const Text('İmzayı Kaydet'),
        ),
      ],
    );
  }
}

class _SigPainter extends CustomPainter {
  const _SigPainter({required this.strokes, required this.current});
  final List<List<NormPoint>> strokes;
  final List<NormPoint> current;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF15326E)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final s in [...strokes, if (current.length >= 2) current]) {
      final path = Path()..moveTo(s.first.x * size.width, s.first.y * size.height);
      for (int i = 1; i < s.length; i++) {
        path.lineTo(s[i].x * size.width, s[i].y * size.height);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter old) => true;
}
