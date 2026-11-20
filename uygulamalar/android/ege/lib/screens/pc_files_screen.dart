import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pc_models.dart';
import '../services/code_tools.dart';
import '../services/device_bridge.dart';
import '../services/pc_bridge_client.dart';
import '../state/jarvis_controller.dart';
import '../widgets/jarvis_ui.dart';
import 'pc_jobs_screen.dart';

const _mono = 'monospace';

String _baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

String _sep(String path) => path.contains('\\') ? '\\' : '/';

// ============================================================ FILE BROWSER

class PcFilesScreen extends StatefulWidget {
  final JarvisController controller;
  final String startPath;
  final String title;

  const PcFilesScreen({
    super.key,
    required this.controller,
    required this.startPath,
    required this.title,
  });

  @override
  State<PcFilesScreen> createState() => _PcFilesScreenState();
}

class _PcFilesScreenState extends State<PcFilesScreen> {
  late String _path;
  PcDirListing? _listing;
  String? _error;
  bool _loading = false;
  bool _showHidden = false;
  final _filterCtrl = TextEditingController();
  final Map<String, double> _scrollMemory = {};
  final _scroll = ScrollController();

  PcBridgeClient get _client => widget.controller.pcClient!;

  @override
  void initState() {
    super.initState();
    _path = widget.startPath;
    _load();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _atStart =>
      _path.toLowerCase() == widget.startPath.toLowerCase() ||
      !_path.toLowerCase().startsWith(widget.startPath.toLowerCase()) ||
      _listing?.parent == null;

  Future<void> _load([String? path]) async {
    if (_scroll.hasClients) _scrollMemory[_path] = _scroll.offset;
    final target = path ?? _path;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await _client.list(target);
      if (!mounted) return;
      setState(() {
        _listing = l;
        _path = l.path;
        _filterCtrl.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final off = _scrollMemory[_path];
        if (_scroll.hasClients) _scroll.jumpTo(off ?? 0);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goUp() {
    final parent = _listing?.parent;
    if (parent != null) _load(parent);
  }

  Future<void> _createItem({required bool dir}) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JColors.surface,
        title: Text(dir ? 'Yeni klasör' : 'Yeni dosya'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: dir ? 'klasor_adi' : 'dosya.dart'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Oluştur')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final created = await _client.create(dir: _path, name: name, directory: dir);
      await _load();
      if (!dir && mounted) _openFile(created);
    } catch (e) {
      if (mounted) showJarvisSnack(context, '$e', error: true);
    }
  }

  Future<void> _uploadHere() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    var n = 0;
    for (final f in picked) {
      try {
        final b = await f.readAsBytes();
        await _client.upload(dir: _path, name: f.name, bytes: b);
        n++;
      } catch (e) {
        if (mounted) showJarvisSnack(context, '${f.name}: $e', error: true);
      }
    }
    if (n > 0) {
      await _load();
      if (mounted) showJarvisSnack(context, '$n dosya PC\'ye gönderildi');
    }
  }

  void _openFile(String path, {int? line}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PcCodeScreen(controller: widget.controller, path: path, initialLine: line),
    ));
  }

  Future<void> _downloadToPhone(PcFileEntry e) async {
    try {
      showJarvisSnack(context, '${e.name} indiriliyor…');
      final bytes = await _client.downloadFile(e.path);
      if (e.ext == '.apk') {
        final msg = await DeviceBridge.installApk(bytes);
        if (mounted) showJarvisSnack(context, msg);
        return;
      }
      final saved = await DeviceBridge.saveBytesToDownloads(bytes: bytes, fileName: e.name);
      if (mounted) {
        showJarvisSnack(context, saved == null ? 'Kaydedilemedi' : 'İndirilenler/Ege içine kaydedildi');
      }
    } catch (err) {
      if (mounted) showJarvisSnack(context, '$err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = (_listing?.entries ?? const <PcFileEntry>[])
        .where((e) => _showHidden || !e.hidden)
        .where((e) => _filterCtrl.text.isEmpty || e.name.toLowerCase().contains(_filterCtrl.text.toLowerCase()))
        .toList();
    final rootPath = _path.toLowerCase().startsWith(widget.startPath.toLowerCase())
        ? widget.startPath
        : (_listing?.root?.path ?? widget.startPath);
    final rel = _path.length > rootPath.length ? _path.substring(rootPath.length) : '';
    final crumbs = rel.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();

    return PopScope(
      canPop: _atStart,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(crumbs.isEmpty ? widget.title : crumbs.last, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                _listing?.root?.name ?? widget.title,
                style:  TextStyle(fontSize: 11.5, color: JColors.muted),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Bu klasörde ara',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PcSearchScreen(
                  controller: widget.controller,
                  root: _path,
                  rootName: crumbs.isEmpty ? widget.title : crumbs.last,
                ),
              )),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'file':
                    await _createItem(dir: false);
                  case 'dir':
                    await _createItem(dir: true);
                  case 'upload':
                    await _uploadHere();
                  case 'git':
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PcGitScreen(controller: widget.controller, path: _path),
                    ));
                  case 'agent':
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PcJobsScreen(controller: widget.controller, initialTab: 0, initialCwd: _path),
                    ));
                  case 'task':
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PcJobsScreen(controller: widget.controller, initialTab: 1, initialCwd: _path),
                    ));
                  case 'hidden':
                    setState(() => _showHidden = !_showHidden);
                  case 'copy':
                    await Clipboard.setData(ClipboardData(text: _path));
                    if (context.mounted) showJarvisSnack(context, 'Yol kopyalandı');
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'agent', child: ListTile(leading: Icon(Icons.smart_toy_rounded), title: Text('Burada kodlama ajanı'))),
                const PopupMenuItem(value: 'task', child: ListTile(leading: Icon(Icons.play_circle_outline_rounded), title: Text('Burada görev çalıştır'))),
                const PopupMenuItem(value: 'git', child: ListTile(leading: Icon(Icons.commit_rounded), title: Text('Git durumu'))),
                const PopupMenuItem(value: 'file', child: ListTile(leading: Icon(Icons.note_add_outlined), title: Text('Yeni dosya'))),
                const PopupMenuItem(value: 'dir', child: ListTile(leading: Icon(Icons.create_new_folder_outlined), title: Text('Yeni klasör'))),
                const PopupMenuItem(value: 'upload', child: ListTile(leading: Icon(Icons.upload_file_rounded), title: Text('Telefondan yükle'))),
                PopupMenuItem(
                  value: 'hidden',
                  child: ListTile(
                    leading: Icon(_showHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    title: Text(_showHidden ? 'Gizlileri sakla' : 'Gizlileri göster'),
                  ),
                ),
                const PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy_rounded), title: Text('Yolu kopyala'))),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _Crumb(
                    label: _listing?.root?.name ?? widget.title,
                    icon: Icons.home_rounded,
                    onTap: () => _load(rootPath),
                  ),
                  for (var i = 0; i < crumbs.length; i++)
                    _Crumb(
                      label: crumbs[i],
                      onTap: () => _load(rootPath + _sep(rootPath) + crumbs.take(i + 1).join(_sep(rootPath))),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: TextField(
                controller: _filterCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.filter_list_rounded, size: 18),
                  hintText: '${_listing?.entries.length ?? 0} öğe içinde süz…',
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _error != null
                  ? _ErrorView(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        controller: _scroll,
                        itemCount: entries.length + (_atStart ? 0 : 1),
                        itemBuilder: (ctx, i) {
                          if (!_atStart && i == 0) {
                            return ListTile(
                              dense: true,
                              leading:  Icon(Icons.drive_folder_upload_rounded, color: JColors.muted),
                              title: const Text('..  (üst klasör)'),
                              onTap: _goUp,
                            );
                          }
                          final e = entries[i - (_atStart ? 0 : 1)];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Icon(
                              fileIconFor(e.name, isDir: e.isDir),
                              color: fileColorFor(e.name, isDir: e.isDir),
                            ),
                            title: Text(
                              e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: e.isDir ? FontWeight.w600 : FontWeight.w400,
                                color: e.hidden ? JColors.muted : JColors.text,
                              ),
                            ),
                            subtitle: Text(
                              e.isDir ? formatAgo(e.modified) : '${formatBytes(e.size)} • ${formatAgo(e.modified)}',
                              style:  TextStyle(fontSize: 11, color: JColors.dim),
                            ),
                            trailing: e.isDir
                                ?  Icon(Icons.chevron_right_rounded, size: 18, color: JColors.dim)
                                : IconButton(
                                    tooltip: e.ext == '.apk' ? 'Telefona kur' : 'Telefona indir',
                                    icon: Icon(
                                      e.ext == '.apk' ? Icons.install_mobile_rounded : Icons.download_rounded,
                                      size: 19,
                                    ),
                                    onPressed: () => _downloadToPhone(e),
                                  ),
                            onTap: () => e.isDir ? _load(e.path) : _openFile(e.path),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _Crumb({required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        avatar: icon == null ? null : Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
        onPressed: onTap,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             Icon(Icons.cloud_off_rounded, size: 40, color: JColors.bad),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style:  TextStyle(color: JColors.muted)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}

// ============================================================ SEARCH

class PcSearchScreen extends StatefulWidget {
  final JarvisController controller;
  final String root;
  final String rootName;

  const PcSearchScreen({
    super.key,
    required this.controller,
    required this.root,
    required this.rootName,
  });

  @override
  State<PcSearchScreen> createState() => _PcSearchScreenState();
}

class _PcSearchScreenState extends State<PcSearchScreen> {
  final _q = TextEditingController();
  final _glob = TextEditingController();
  bool _byName = false;
  bool _regex = false;
  bool _case = false;
  bool _loading = false;
  String? _error;
  List<PcSearchHit> _hits = const [];
  bool _truncated = false;

  @override
  void dispose() {
    _q.dispose();
    _glob.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_q.text.trim().length < 2) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.controller.pcClient!.search(
        root: widget.root,
        query: _q.text.trim(),
        byName: _byName,
        glob: _glob.text,
        regex: _regex,
        caseSensitive: _case,
      );
      if (!mounted) return;
      setState(() {
        _hits = r.hits;
        _truncated = r.truncated;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<PcSearchHit>>{};
    for (final h in _hits) {
      grouped.putIfAbsent(h.path, () => []).add(h);
    }
    return Scaffold(
      appBar: AppBar(title: Text('Ara • ${widget.rootName}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _q,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                hintText: _byName ? 'Dosya adı (ör. *.dart, controller)' : 'Kod içinde aranacak metin',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _run),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                ChoiceChip(label: const Text('İçerik'), selected: !_byName, onSelected: (_) => setState(() => _byName = false)),
                const SizedBox(width: 6),
                ChoiceChip(label: const Text('Dosya adı'), selected: _byName, onSelected: (_) => setState(() => _byName = true)),
                const SizedBox(width: 6),
                if (!_byName) ...[
                  FilterChip(label: const Text('Regex'), selected: _regex, onSelected: (v) => setState(() => _regex = v)),
                  const SizedBox(width: 6),
                  FilterChip(label: const Text('Aa'), selected: _case, onSelected: (v) => setState(() => _case = v)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _glob,
                      decoration: const InputDecoration(isDense: true, hintText: '*.dart,*.kt'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style:  TextStyle(color: JColors.bad))),
          if (!_loading && _hits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
              child: Row(
                children: [
                  Text('${_hits.length} sonuç • ${grouped.length} dosya${_truncated ? ' (sınırlandı)' : ''}',
                      style:  TextStyle(fontSize: 12, color: JColors.muted)),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final entry in grouped.entries) ...[
                  ListTile(
                    dense: true,
                    leading: Icon(fileIconFor(entry.key), color: fileColorFor(entry.key), size: 20),
                    title: Text(entry.value.first.rel, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    onTap: () => _open(entry.key),
                  ),
                  if (!_byName)
                    for (final h in entry.value.take(8))
                      InkWell(
                        onTap: () => _open(h.path, line: h.line),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(56, 2, 12, 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 42,
                                child: Text('${h.line}', style:  TextStyle(fontFamily: _mono, fontSize: 11, color: JColors.dim)),
                              ),
                              Expanded(
                                child: Text.rich(
                                  CodeHighlighter.highlightLine(h.text, CodeLang.detect(h.path)),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontFamily: _mono, fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _open(String path, {int? line}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PcCodeScreen(controller: widget.controller, path: path, initialLine: line),
    ));
  }
}

// ============================================================ CODE VIEWER / EDITOR

class PcCodeScreen extends StatefulWidget {
  final JarvisController controller;
  final String path;
  final int? initialLine;

  const PcCodeScreen({
    super.key,
    required this.controller,
    required this.path,
    this.initialLine,
  });

  @override
  State<PcCodeScreen> createState() => _PcCodeScreenState();
}

class _PcCodeScreenState extends State<PcCodeScreen> {
  PcFileContent? _file;
  String _text = '';
  List<String> _lines = const [];
  List<TextSpan> _spans = const [];
  String? _error;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _aiBusy = false;
  double _fontSize = 12.5;
  final _editCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _findCtrl = TextEditingController();
  bool _findOpen = false;
  List<int> _matches = const [];
  int _matchIdx = 0;
  int? _highlightLine;

  late final String _lang = CodeLang.detect(widget.path);

  PcBridgeClient get _client => widget.controller.pcClient!;

  bool get _dirty => _editing && _editCtrl.text != _text;

  double get _lineHeight => _fontSize * 1.55;

  @override
  void initState() {
    super.initState();
    _highlightLine = widget.initialLine;
    _load();
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    _scroll.dispose();
    _findCtrl.dispose();
    super.dispose();
  }

  void _setText(String text) {
    _text = text;
    _lines = text.split('\n');
    _spans = _lines.length <= 6000
        ? CodeHighlighter.highlightLines(_lines, _lang)
        : [for (final l in _lines) TextSpan(text: l, style: const TextStyle(color: CodePalette.base))];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = await _client.read(widget.path);
      if (!mounted) return;
      setState(() {
        _file = f;
        _setText(f.content.replaceAll('\r\n', '\n'));
      });
      if (_highlightLine != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_highlightLine! - 1));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _jumpTo(int lineIdx) {
    if (!_scroll.hasClients) return;
    final target = (lineIdx * _lineHeight - 120).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _runFind() {
    final q = _findCtrl.text.toLowerCase();
    final m = <int>[];
    if (q.isNotEmpty) {
      for (var i = 0; i < _lines.length; i++) {
        if (_lines[i].toLowerCase().contains(q)) m.add(i);
      }
    }
    setState(() {
      _matches = m;
      _matchIdx = 0;
      _highlightLine = m.isEmpty ? null : m.first + 1;
    });
    if (m.isNotEmpty) _jumpTo(m.first);
  }

  void _nextMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _matchIdx = (_matchIdx + delta) % _matches.length;
      if (_matchIdx < 0) _matchIdx += _matches.length;
      _highlightLine = _matches[_matchIdx] + 1;
    });
    _jumpTo(_matches[_matchIdx]);
  }

  Future<void> _toggleEdit() async {
    if (!_editing) {
      setState(() {
        _editCtrl.text = _text;
        _editing = true;
      });
      return;
    }
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: JColors.surface,
          title: const Text('Değişiklikler kaydedilmedi'),
          content: const Text('Düzenlemeden çıkılırsa değişiklikler silinir.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Düzenlemeye dön')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Değişiklikleri at')),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => _editing = false);
  }

  String _restoreEol(String text) =>
      _file?.eol == 'crlf' ? text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n') : text;

  Future<bool> _save(String newText, {bool force = false}) async {
    final f = _file;
    if (f == null) return false;
    setState(() => _saving = true);
    try {
      final res = await _client.write(
        path: f.path,
        content: _restoreEol(newText),
        baseSha: force ? null : f.sha256,
        encoding: f.encoding,
      );
      if (!mounted) return true;
      setState(() {
        _file = PcFileContent(
          path: f.path,
          name: f.name,
          size: res.size,
          content: newText,
          encoding: f.encoding,
          sha256: res.sha256,
          eol: f.eol,
        );
        _setText(newText);
        _editing = false;
      });
      showJarvisSnack(context, 'PC\'ye kaydedildi • ${formatBytes(res.size)} (yedek alındı)');
      return true;
    } on PcBridgeException catch (e) {
      if (!mounted) return false;
      if (e.conflict) {
        final overwrite = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: JColors.surface,
            title: const Text('Dosya PC\'de değişmiş'),
            content: const Text('Bu dosya siz açtıktan sonra PC\'de değiştirilmiş. Üzerine yazılsın mı? (Eski hali yedeklenir.)'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Üzerine yaz')),
            ],
          ),
        );
        if (overwrite == true) return _save(newText, force: true);
      } else {
        showJarvisSnack(context, e.message, error: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _aiEdit() async {
    final instruction = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JColors.surface,
      showDragHandle: true,
      builder: (ctx) => _AiInstructionSheet(fileName: _baseName(widget.path), model: widget.controller.settings.model),
    );
    if (instruction == null || instruction.trim().isEmpty || !mounted) return;
    final base = _editing ? _editCtrl.text : _text;
    setState(() => _aiBusy = true);
    final res = await widget.controller.aiEditCode(path: widget.path, content: base, instruction: instruction);
    if (!mounted) return;
    setState(() => _aiBusy = false);
    if (!res.ok) {
      showJarvisSnack(context, res.error ?? 'AI düzenleme başarısız.', error: true);
      return;
    }
    final newCode = base.endsWith('\n') || !res.code.endsWith('\n')
        ? res.code
        : res.code.substring(0, res.code.length - 1);
    final apply = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PcDiffScreen(
        title: _baseName(widget.path),
        oldText: base,
        newText: newCode,
        summary: res.summary,
        applyLabel: 'Uygula ve PC\'ye Kaydet',
      ),
    ));
    if (apply == true) {
      await _save(newCode);
    }
  }

  Future<void> _explain() async {
    final prompt = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: JColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in const [
              ('Bu dosyayı açıkla: ne yapıyor, ana parçaları neler?', Icons.menu_book_rounded),
              ('Bu dosyadaki olası hataları ve riskleri bul, düzeltme öner.', Icons.bug_report_rounded),
              ('Bu kod için performans ve okunabilirlik iyileştirmeleri öner.', Icons.speed_rounded),
              ('Bu dosya için birim testleri yaz.', Icons.fact_check_rounded),
            ])
              ListTile(
                leading: Icon(p.$2, color: JColors.primary),
                title: Text(p.$1, style: const TextStyle(fontSize: 13.5)),
                onTap: () => Navigator.pop(ctx, p.$1),
              ),
          ],
        ),
      ),
    );
    if (prompt == null || !mounted) return;
    final nav = Navigator.of(context);
    await widget.controller.sendCodeToChat(
      path: widget.path,
      content: _editing ? _editCtrl.text : _text,
      prompt: prompt,
    );
    nav.popUntil((r) => r.isFirst);
  }

  Future<void> _download() async {
    try {
      final bytes = await _client.downloadFile(widget.path);
      final saved = await DeviceBridge.saveBytesToDownloads(bytes: bytes, fileName: _baseName(widget.path));
      if (mounted) showJarvisSnack(context, saved == null ? 'Kaydedilemedi' : 'İndirilenler/Ege içine kaydedildi');
    } catch (e) {
      if (mounted) showJarvisSnack(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: JColors.surface,
            title: const Text('Kaydedilmemiş değişiklikler'),
            content: const Text('Değişiklikler kaydedilmedi. Çıkılsın mı?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kal')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydetmeden çık')),
            ],
          ),
        );
        if (leave == true) {
          setState(() => _editing = false);
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_baseName(widget.path), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                f == null
                    ? CodeLang.label(_lang)
                    : '${CodeLang.label(_lang)} • ${_lines.length} satır • ${formatBytes(f.size)}${_dirty ? ' • değişti' : ''}',
                style: TextStyle(fontSize: 11.5, color: _dirty ? JColors.warn : JColors.muted),
              ),
            ],
          ),
          actions: [
            if (f != null && f.editable && !_editing)
              IconButton(
                tooltip: 'Bul',
                onPressed: () => setState(() => _findOpen = !_findOpen),
                icon: const Icon(Icons.find_in_page_outlined),
              ),
            if (f != null && f.editable)
              IconButton(
                tooltip: _editing ? 'Görüntüleme' : 'Düzenle',
                onPressed: _toggleEdit,
                icon: Icon(_editing ? Icons.visibility_rounded : Icons.edit_rounded),
              ),
            if (_dirty)
              IconButton(
                tooltip: 'Kaydet',
                onPressed: _saving ? null : () => _save(_editCtrl.text),
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    :  Icon(Icons.save_rounded, color: JColors.ok),
              ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'ai':
                    await _aiEdit();
                  case 'explain':
                    await _explain();
                  case 'git':
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PcGitScreen(controller: widget.controller, path: widget.path, initialTab: 1),
                    ));
                  case 'copy':
                    await Clipboard.setData(ClipboardData(text: _editing ? _editCtrl.text : _text));
                    if (context.mounted) showJarvisSnack(context, 'İçerik panoya kopyalandı');
                  case 'path':
                    await Clipboard.setData(ClipboardData(text: widget.path));
                    if (context.mounted) showJarvisSnack(context, 'Yol kopyalandı');
                  case 'download':
                    await _download();
                  case 'reload':
                    await _load();
                  case 'bigger':
                    setState(() => _fontSize = math.min(20, _fontSize + 1));
                  case 'smaller':
                    setState(() => _fontSize = math.max(9, _fontSize - 1));
                  case 'agent':
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PcJobsScreen(
                        controller: widget.controller,
                        initialTab: 0,
                        initialCwd: widget.path,
                        initialPrompt: '${_baseName(widget.path)} dosyasında: ',
                      ),
                    ));
                }
              },
              itemBuilder: (_) => [
                if (f != null && f.editable) ...[
                   PopupMenuItem(value: 'ai', child: ListTile(leading: Icon(Icons.auto_fix_high_rounded, color: JColors.violet), title: Text('AI ile düzenle'))),
                  const PopupMenuItem(value: 'explain', child: ListTile(leading: Icon(Icons.forum_rounded), title: Text('Sohbette incele'))),
                  const PopupMenuItem(value: 'agent', child: ListTile(leading: Icon(Icons.smart_toy_rounded), title: Text('Kodlama ajanına ver'))),
                ],
                const PopupMenuItem(value: 'git', child: ListTile(leading: Icon(Icons.difference_rounded), title: Text('Git farkı'))),
                const PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy_all_rounded), title: Text('İçeriği kopyala'))),
                const PopupMenuItem(value: 'path', child: ListTile(leading: Icon(Icons.link_rounded), title: Text('Yolu kopyala'))),
                const PopupMenuItem(value: 'download', child: ListTile(leading: Icon(Icons.download_rounded), title: Text('Telefona indir'))),
                const PopupMenuItem(value: 'reload', child: ListTile(leading: Icon(Icons.refresh_rounded), title: Text('PC\'den yeniden yükle'))),
                const PopupMenuItem(value: 'bigger', child: ListTile(leading: Icon(Icons.text_increase_rounded), title: Text('Yazıyı büyüt'))),
                const PopupMenuItem(value: 'smaller', child: ListTile(leading: Icon(Icons.text_decrease_rounded), title: Text('Yazıyı küçült'))),
              ],
            ),
          ],
        ),
        floatingActionButton: f != null && f.editable && !_aiBusy
            ? FloatingActionButton.extended(
                heroTag: 'ai_edit_fab',
                backgroundColor: JColors.violet,
                foregroundColor: Colors.white,
                onPressed: _aiEdit,
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const Text('AI ile düzenle'),
              )
            : null,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);
    final f = _file!;
    if (_aiBusy) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             CircularProgressIndicator(color: JColors.violet),
            const SizedBox(height: 14),
            Text('${widget.controller.settings.model} kodu düzenliyor…', style:  TextStyle(color: JColors.muted)),
          ],
        ),
      );
    }
    if (f.image && f.imageBase64 != null) {
      return InteractiveViewer(maxScale: 8, child: Center(child: Image.memory(base64Decode(f.imageBase64!))));
    }
    if (f.binary) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(fileIconFor(f.name), size: 48, color: JColors.muted),
            const SizedBox(height: 10),
            Text('İkili dosya • ${formatBytes(f.size)}', style:  TextStyle(color: JColors.muted)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _download, icon: const Icon(Icons.download_rounded), label: const Text('Telefona indir')),
          ],
        ),
      );
    }
    if (_editing) {
      return Container(
        color: JColors.code,
        child: TextField(
          controller: _editCtrl,
          maxLines: null,
          expands: true,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          onChanged: (_) => setState(() {}),
          style: TextStyle(fontFamily: _mono, fontSize: _fontSize, height: 1.45, color: CodePalette.base),
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 90),
          ),
        ),
      );
    }
    final gutterW = (_lines.length.toString().length * _fontSize * 0.62) + 18;
    final maxLen = _lines.fold<int>(0, (m, l) => math.max(m, l.length));
    final contentW = math.max(MediaQuery.of(context).size.width, gutterW + maxLen * _fontSize * 0.61 + 40);
    return Column(
      children: [
        if (f.truncated)
          Container(
            width: double.infinity,
            color: const Color(0xFF422006),
            padding: const EdgeInsets.all(8),
            child:  Text('Dosya çok büyük; yalnız ilk kısmı gösteriliyor (düzenleme kapalı).',
                style: TextStyle(fontSize: 12, color: JColors.warn)),
          ),
        if (_findOpen)
          Container(
            color: JColors.surface,
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _findCtrl,
                    autofocus: true,
                    onSubmitted: (_) => _runFind(),
                    onChanged: (_) => _runFind(),
                    decoration: const InputDecoration(isDense: true, hintText: 'Dosyada bul'),
                  ),
                ),
                Text(_matches.isEmpty ? '0' : '${_matchIdx + 1}/${_matches.length}',
                    style:  TextStyle(fontSize: 12, color: JColors.muted)),
                IconButton(onPressed: () => _nextMatch(-1), icon: const Icon(Icons.keyboard_arrow_up_rounded)),
                IconButton(onPressed: () => _nextMatch(1), icon: const Icon(Icons.keyboard_arrow_down_rounded)),
              ],
            ),
          ),
        Expanded(
          child: Container(
            color: JColors.code,
            child: Scrollbar(
              controller: _scroll,
              notificationPredicate: (n) => n.depth == 1,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentW,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(top: 8, bottom: 96),
                    itemExtent: _lineHeight,
                    itemCount: _lines.length,
                    itemBuilder: (ctx, i) {
                      final hl = _highlightLine == i + 1;
                      return Container(
                        color: hl ? JColors.primary.withValues(alpha: 0.13) : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: gutterW,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(fontFamily: _mono, fontSize: _fontSize * 0.86, color: hl ? JColors.accent : const Color(0xFF3B4A61)),
                              ),
                            ),
                            Expanded(
                              child: Text.rich(
                                _spans[i],
                                softWrap: false,
                                maxLines: 1,
                                style: TextStyle(fontFamily: _mono, fontSize: _fontSize, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AiInstructionSheet extends StatefulWidget {
  final String fileName;
  final String model;

  const _AiInstructionSheet({required this.fileName, required this.model});

  @override
  State<_AiInstructionSheet> createState() => _AiInstructionSheetState();
}

class _AiInstructionSheetState extends State<_AiInstructionSheet> {
  final _ctrl = TextEditingController();

  static const _quick = [
    'Hataları ve olası çökmeleri düzelt',
    'Kodu sadeleştir ve okunabilir yap',
    'Eksik hata yönetimini ekle',
    'Kısa Türkçe açıklama yorumları ekle',
    'Performansı iyileştir',
    'Arayüz metinlerini Türkçeleştir',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
               Icon(Icons.auto_fix_high_rounded, color: JColors.violet),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${widget.fileName} • AI ile düzenle',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          Text('Model: ${widget.model}', style:  TextStyle(fontSize: 11.5, color: JColors.muted)),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            autofocus: true,
            minLines: 3,
            maxLines: 7,
            decoration: const InputDecoration(
              hintText: 'Ne değişsin? Ör: "Ayarlar ekranına koyu/açık tema seçeneği ekle"',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final q in _quick)
                ActionChip(
                  label: Text(q, style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => setState(() => _ctrl.text = q),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: JColors.violet),
              onPressed: () => Navigator.pop(context, _ctrl.text),
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('Değişikliği hazırla (önce farkı göreceksin)'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ DIFF

class PcDiffScreen extends StatelessWidget {
  final String title;
  final String oldText;
  final String newText;
  final String summary;
  final String applyLabel;

  const PcDiffScreen({
    super.key,
    required this.title,
    required this.oldText,
    required this.newText,
    this.summary = '',
    this.applyLabel = 'Uygula',
  });

  @override
  Widget build(BuildContext context) {
    final lines = LineDiff.compute(oldText, newText);
    final st = LineDiff.stats(lines);
    final hunks = LineDiff.hunks(lines);
    return Scaffold(
      appBar: AppBar(
        title: Text('Fark • $title'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(26),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Pill('+${st.added}', color: JColors.ok),
                const SizedBox(width: 6),
                Pill('−${st.removed}', color: JColors.bad),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (summary.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: JColors.violet.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JColors.violet.withValues(alpha: 0.35)),
              ),
              child: Text(summary, style: const TextStyle(fontSize: 12.5, height: 1.4)),
            ),
          Expanded(
            child: st.added + st.removed == 0
                ?  Center(child: Text('Değişiklik yok.', style: TextStyle(color: JColors.muted)))
                : Container(
                    color: JColors.code,
                    child: ListView.builder(
                      itemCount: hunks.length,
                      itemBuilder: (ctx, i) {
                        final l = hunks[i];
                        if (l == null) {
                          return Container(
                            color: const Color(0xFF0C1A2E),
                            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
                            child:  Text('⋯', style: TextStyle(color: JColors.dim)),
                          );
                        }
                        final color = switch (l.kind) {
                          DiffKind.add => const Color(0xFF0B3B2A),
                          DiffKind.del => const Color(0xFF3F1219),
                          DiffKind.same => Colors.transparent,
                        };
                        final sign = switch (l.kind) {
                          DiffKind.add => '+',
                          DiffKind.del => '−',
                          DiffKind.same => ' ',
                        };
                        return Container(
                          color: color,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 38,
                                child: Text(
                                  '${l.kind == DiffKind.add ? l.newNo : l.oldNo}',
                                  textAlign: TextAlign.right,
                                  style:  TextStyle(fontFamily: _mono, fontSize: 10.5, color: JColors.dim),
                                ),
                              ),
                              SizedBox(
                                width: 16,
                                child: Text(sign,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: _mono,
                                      fontSize: 12,
                                      color: l.kind == DiffKind.add
                                          ? JColors.ok
                                          : l.kind == DiffKind.del
                                              ? JColors.bad
                                              : JColors.dim,
                                    )),
                              ),
                              Expanded(
                                child: Text(
                                  l.text,
                                  style: TextStyle(
                                    fontFamily: _mono,
                                    fontSize: 11.5,
                                    color: l.kind == DiffKind.same ? JColors.muted : JColors.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: st.added + st.removed == 0 ? null : () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(applyLabel),
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

// ============================================================ GIT

class PcGitScreen extends StatefulWidget {
  final JarvisController controller;
  final String path;
  final int initialTab;

  const PcGitScreen({
    super.key,
    required this.controller,
    required this.path,
    this.initialTab = 0,
  });

  @override
  State<PcGitScreen> createState() => _PcGitScreenState();
}

class _PcGitScreenState extends State<PcGitScreen> {
  static const _ops = ['status', 'diff', 'log'];
  final Map<String, Map<String, dynamic>> _data = {};
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    for (final op in _ops) {
      _load(op);
    }
  }

  Future<void> _load(String op) async {
    try {
      final d = await widget.controller.pcClient!.git(widget.path, op);
      if (mounted) setState(() => _data[op] = d);
    } catch (e) {
      if (mounted) setState(() => _errors[op] = '$e');
    }
  }

  Widget _output(String op) {
    if (_errors[op] != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_errors[op]!, style:  TextStyle(color: JColors.bad))));
    }
    final d = _data[op];
    if (d == null) return const Center(child: CircularProgressIndicator());
    if (op == 'log' && d['commits'] is List) {
      final commits = (d['commits'] as List).whereType<Map>().toList();
      return ListView.separated(
        itemCount: commits.length,
        separatorBuilder: (_, _) =>  Divider(height: 1, color: JColors.border),
        itemBuilder: (ctx, i) {
          final cm = commits[i];
          return ListTile(
            dense: true,
            leading: Text('${cm['hash']}', style:  TextStyle(fontFamily: _mono, color: JColors.warn, fontSize: 12)),
            title: Text('${cm['subject']}', style: const TextStyle(fontSize: 13)),
            subtitle: Text('${cm['author']} • ${cm['when']}', style:  TextStyle(fontSize: 11, color: JColors.dim)),
            onTap: () async {
              try {
                final show = await widget.controller.pcClient!.git(widget.path, 'show', rev: '${cm['hash']}');
                if (!ctx.mounted) return;
                Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text('Commit ${cm['hash']}')),
                    body: _GitTextView(text: '${show['output'] ?? ''}'),
                  ),
                ));
              } catch (e) {
                if (ctx.mounted) showJarvisSnack(ctx, '$e', error: true);
              }
            },
          );
        },
      );
    }
    final text = '${d['output'] ?? ''}'.trim();
    return _GitTextView(text: text.isEmpty ? (op == 'diff' ? 'Kaydedilmemiş değişiklik yok.' : '(boş)') : text);
  }

  @override
  Widget build(BuildContext context) {
    final repo = _data.values.map((d) => d['repo']).whereType<String>().firstOrNull;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Git'),
              Text(repo ?? widget.path, style:  TextStyle(fontSize: 11, color: JColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () {
                setState(() {
                  _data.clear();
                  _errors.clear();
                });
                for (final op in _ops) {
                  _load(op);
                }
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Durum'), Tab(text: 'Fark'), Tab(text: 'Geçmiş')]),
        ),
        body: TabBarView(children: [for (final op in _ops) _output(op)]),
      ),
    );
  }
}

class _GitTextView extends StatelessWidget {
  final String text;

  const _GitTextView({required this.text});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Container(
      color: JColors.code,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(
            MediaQuery.of(context).size.width,
            lines.fold<int>(0, (m, l) => math.max(m, l.length)) * 7.2 + 30,
          ),
          child: ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: lines.length,
            itemBuilder: (ctx, i) {
              final l = lines[i];
              Color color = JColors.muted;
              Color? bg;
              if (l.startsWith('+') && !l.startsWith('+++')) {
                color = JColors.ok;
                bg = const Color(0xFF0B3B2A);
              } else if (l.startsWith('-') && !l.startsWith('---')) {
                color = JColors.bad;
                bg = const Color(0xFF3F1219);
              } else if (l.startsWith('@@')) {
                color = JColors.accent;
              } else if (l.startsWith('diff ') || l.startsWith('commit ')) {
                color = JColors.warn;
              } else if (RegExp(r'^\s?[MADRCU?]{1,2}\s').hasMatch(l) || l.startsWith('##')) {
                color = JColors.text;
              }
              return Container(
                color: bg,
                child: Text(l, softWrap: false, style: TextStyle(fontFamily: _mono, fontSize: 11.5, color: color, height: 1.35)),
              );
            },
          ),
        ),
      ),
    );
  }
}
