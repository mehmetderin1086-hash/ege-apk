import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/device_bridge.dart';
import '../services/work_hub.dart';
import '../state/jarvis_controller.dart';
import '../widgets/jarvis_ui.dart';
import '../widgets/markdown_message.dart';
import 'agent_center_screen.dart';
import 'memory_screen.dart';
import 'youtube_screen.dart';
import '../widgets/chat_palette.dart';
import '../widgets/ege_banner_art.dart';

IconData workIcon(String kind) => switch (kind) {
      WorkKind.research => Icons.travel_explore_rounded,
      WorkKind.scrape => Icons.data_object_rounded,
      WorkKind.download => Icons.download_rounded,
      WorkKind.video => Icons.movie_rounded,
      WorkKind.audio => Icons.music_note_rounded,
      WorkKind.word => Icons.description_rounded,
      WorkKind.excel => Icons.table_chart_rounded,
      WorkKind.pdf => Icons.picture_as_pdf_rounded,
      WorkKind.txt => Icons.article_rounded,
      WorkKind.ocr => Icons.document_scanner_rounded,
      WorkKind.summarize => Icons.summarize_rounded,
      WorkKind.zip => Icons.folder_zip_rounded,
      WorkKind.unzip => Icons.unarchive_rounded,
      _ => Icons.work_outline_rounded,
    };

Color workColor(String kind) => switch (kind) {
      WorkKind.word => const Color(0xFF60A5FA),
      WorkKind.excel => const Color(0xFF34D399),
      WorkKind.pdf => const Color(0xFFF87171),
      WorkKind.research => JColors.primary,
      WorkKind.video || WorkKind.audio => const Color(0xFFF472B6),
      WorkKind.ocr || WorkKind.summarize => JColors.violet,
      _ => JColors.warn,
    };

(String, Color) statusLook(String status) => switch (status) {
      'running' => ('Çalışıyor', JColors.primary),
      'queued' => ('Sırada', JColors.warn),
      'scheduled' => ('Zamanlandı', JColors.violet),
      'completed' => ('Tamamlandı', JColors.ok),
      'cancelled' => ('İptal', JColors.muted),
      _ => ('Hata', JColors.bad),
    };

/// Compact hub card shown at the top of the Studio tab.
class StudioHubCard extends StatelessWidget {
  final JarvisController controller;

  const StudioHubCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final active = c.works.activeCount;
    final last = c.works.jobs.firstOrNull;
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        glow: JColors.accent,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 116,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const EgeBannerArt(),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            JColors.bg.withValues(alpha: 0.94),
                            JColors.bg.withValues(alpha: 0.45),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                               Icon(Icons.hub_rounded, color: JColors.accent, size: 20),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Ege Merkezi',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, letterSpacing: 0.3),
                                ),
                              ),
                              if (active > 0) Pill('$active iş çalışıyor', icon: Icons.sync_rounded),
                            ],
                          ),
                          const SizedBox(height: 4),
                           Text(
                            'İşler, müzik ve hafıza tek merkezde',
                            style: TextStyle(fontSize: 12, color: JColors.muted),
                          ),
                          const Spacer(),
                          if (last != null)
                            Text(
                              'Son iş: ${WorkKind.label(last.kind)} — ${last.title} • ${statusLook(last.status).$1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: ChatPalette.ink),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
              children: [
                Expanded(
                  child: QuickTile(
                    icon: Icons.work_history_rounded,
                    label: 'Çalışmalar',
                    subtitle: 'Word • Excel • PDF',
                    color: JColors.violet,
                    onTap: () => push(WorksScreen(controller: c)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: QuickTile(
                    icon: Icons.smart_display_rounded,
                    label: 'YouTube',
                    subtitle: c.musicNow == null ? 'Müzik çal' : 'Çalıyor',
                    color: const Color(0xFFF472B6),
                    onTap: () => push(YoutubeScreen(controller: c)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: QuickTile(
                    icon: Icons.psychology_alt_rounded,
                    label: 'Hafıza',
                    subtitle: '${c.memoryItems.length} bilgi',
                    color: JColors.ok,
                    onTap: () => push(MemoryScreen(controller: c)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: QuickTile(
                    icon: Icons.hub_rounded,
                    label: 'Ajan Merkezi',
                    subtitle: 'Hermes',
                    color: JColors.warn,
                    onTap: () => push(AgentCenterScreen(controller: c)),
                  ),
                ),
              ],
            ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorksScreen extends StatefulWidget {
  final JarvisController controller;
  final String? initialKind;

  const WorksScreen({super.key, required this.controller, this.initialKind});

  @override
  State<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends State<WorksScreen> {
  String _filter = 'all';
  String _query = '';

  JarvisController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (widget.initialKind != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _create(kind: widget.initialKind));
    }
  }

  Future<void> _create({String? kind}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JColors.surface,
      showDragHandle: true,
      builder: (_) => WorkCreateSheet(controller: c, initialKind: kind),
    );
  }

  bool _match(WorkJob j) {
    final ok = switch (_filter) {
      'active' => j.active,
      'done' => j.status == 'completed',
      'failed' => j.status == 'failed' || j.status == 'cancelled',
      _ => true,
    };
    if (!ok) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return j.task.toLowerCase().contains(q) || WorkKind.label(j.kind).toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c.works,
      builder: (context, _) {
        final list = c.works.jobs.where(_match).toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Çalışmalar'),
            actions: [
              IconButton(
                tooltip: 'Bitenleri temizle',
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Bitenler temizlensin mi?'),
                      content: const Text('Tamamlanan, iptal edilen ve hatalı işler listeden silinir. '
                          'İndirilenler klasörüne kaydedilen dosyalar kalır.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Temizle')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final n = await c.works.clearFinished();
                    if (context.mounted) showJarvisSnack(context, '$n iş temizlendi');
                  }
                },
                icon: const Icon(Icons.cleaning_services_outlined),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'works_fab',
            onPressed: _create,
            icon: const Icon(Icons.add_task_rounded),
            label: const Text('Yeni İş'),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    hintText: 'İşlerde ara',
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    for (final f in const [('all', 'Tümü'), ('active', 'Aktif'), ('done', 'Tamamlanan'), ('failed', 'Hatalı / İptal')]) ...[
                      ChoiceChip(
                        label: Text(f.$2),
                        selected: _filter == f.$1,
                        onSelected: (_) => setState(() => _filter = f.$1),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? _EmptyWorks(onStart: (k) => _create(kind: k))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        itemCount: list.length,
                        itemBuilder: (ctx, i) => _JobCard(controller: c, job: list[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyWorks extends StatelessWidget {
  final void Function(String kind) onStart;

  const _EmptyWorks({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
         Icon(Icons.work_history_rounded, size: 54, color: JColors.violet),
        const SizedBox(height: 10),
        const Text(
          'Arka planda çalışan işler',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
         Text(
          'Word/Excel/PDF belgesi üret, web araştırması yap, PDF/fotoğrafı metne çevir, YouTube\'dan '
          'müzik indir. Sesle de olur: "word oluştur: haftalık rapor".',
          textAlign: TextAlign.center,
          style: TextStyle(color: JColors.muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final k in WorkKind.all)
              ActionChip(
                avatar: Icon(workIcon(k), size: 16, color: workColor(k)),
                label: Text(WorkKind.label(k)),
                onPressed: () => onStart(k),
              ),
          ],
        ),
      ],
    );
  }
}

class _JobCard extends StatelessWidget {
  final JarvisController controller;
  final WorkJob job;

  const _JobCard({required this.controller, required this.job});

  Future<void> _openOutput(BuildContext context, WorkFile o) async {
    final target = o.publicUri ?? o.path;
    final ok = await DeviceBridge.openFileUri(target, mimeType: o.mime);
    if (!ok && context.mounted) showJarvisSnack(context, 'Dosya açılamadı: ${o.name}', error: true);
  }

  Future<void> _share(WorkJob j) async {
    final files = j.outputs.where((o) => o.path.isNotEmpty).map((o) => XFile(o.path)).toList();
    await SharePlus.instance.share(
      ShareParams(
        text: files.isEmpty ? j.summary : '${WorkKind.label(j.kind)}: ${j.title}',
        files: files.isEmpty ? null : files,
      ),
    );
  }

  void _details(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JColors.surface,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(job.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${WorkKind.label(job.kind)} • ${statusLook(job.status).$1}',
                style:  TextStyle(color: JColors.muted, fontSize: 12.5)),
            if (job.error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(job.error, style:  TextStyle(color: JColors.bad)),
            ],
            const SizedBox(height: 12),
            if (job.summary.isNotEmpty) MarkdownMessage(text: job.summary),
            if (job.outputs.isNotEmpty) ...[
              const SectionTitle('Çıktılar', icon: Icons.attach_file_rounded),
              for (final o in job.outputs)
                ListTile(
                  dense: true,
                  leading: Icon(fileIconFor(o.name), color: fileColorFor(o.name)),
                  title: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatBytes(o.size)),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _openOutput(ctx, o),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (statusText, statusColor) = statusLook(job.status);
    final color = workColor(job.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        glow: statusColor,
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        onTap: () => _details(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(workIcon(job.kind), color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Pill(statusText, color: statusColor),
                          Text(WorkKind.label(job.kind), style:  TextStyle(fontSize: 11.5, color: JColors.muted)),
                          Text(
                            job.status == 'scheduled' && job.runAt != null
                                ? '⏰ ${MaterialLocalizations.of(context).formatShortDate(job.runAt!)} '
                                    '${TimeOfDay.fromDateTime(job.runAt!).format(context)}'
                                : formatAgo(job.createdAt),
                            style:  TextStyle(fontSize: 11, color: JColors.dim),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    final w = controller.works;
                    switch (v) {
                      case 'cancel':
                        await w.cancel(job.id);
                      case 'retry':
                        await w.retry(job.id);
                      case 'chat':
                        await controller.transferWorkToChat(job);
                        if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                      case 'copy':
                        await Clipboard.setData(ClipboardData(text: job.summary));
                        if (context.mounted) showJarvisSnack(context, 'Sonuç kopyalandı');
                      case 'share':
                        await _share(job);
                      case 'delete':
                        await w.remove(job.id);
                    }
                  },
                  itemBuilder: (_) => [
                    if (job.active) const PopupMenuItem(value: 'cancel', child: Text('İptal et')),
                    if (!job.active) const PopupMenuItem(value: 'retry', child: Text('Yeniden dene')),
                    if (job.status == 'completed') ...const [
                      PopupMenuItem(value: 'chat', child: Text('💬 Sohbete aktar')),
                      PopupMenuItem(value: 'copy', child: Text('📋 Sonucu kopyala')),
                      PopupMenuItem(value: 'share', child: Text('Paylaş')),
                    ],
                    const PopupMenuItem(value: 'delete', child: Text('🗑 Sil')),
                  ],
                ),
              ],
            ),
            if (job.active) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: LinearProgressIndicator(value: job.status == 'running' ? job.progress : 0),
              ),
              const SizedBox(height: 4),
              Text(job.stage, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style:  TextStyle(fontSize: 11.5, color: JColors.accent)),
            ],
            if (job.status == 'failed' && job.error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(job.error, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style:  TextStyle(fontSize: 12, color: JColors.bad)),
            ],
            if (job.status == 'completed') ...[
              if (job.outputs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final o in job.outputs.take(4))
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(fileIconFor(o.name), size: 15, color: fileColorFor(o.name)),
                        label: Text(o.name.length > 26 ? '${o.name.substring(0, 26)}…' : o.name,
                            style: const TextStyle(fontSize: 11.5)),
                        onPressed: () => _openOutput(context, o),
                      ),
                  ],
                ),
              ] else if (job.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(job.summary, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style:  TextStyle(fontSize: 12, color: JColors.muted)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that creates a new job (kind, task, source files, schedule).
class WorkCreateSheet extends StatefulWidget {
  final JarvisController controller;
  final String? initialKind;

  const WorkCreateSheet({super.key, required this.controller, this.initialKind});

  @override
  State<WorkCreateSheet> createState() => _WorkCreateSheetState();
}

class _WorkCreateSheetState extends State<WorkCreateSheet> {
  late String _kind = widget.initialKind ?? WorkKind.word;
  final _task = TextEditingController();
  final List<PlatformFile> _files = [];
  DateTime? _runAt;
  bool _starting = false;

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  bool get _allowsSources => WorkKind.needsSources(_kind) ||
      const {WorkKind.word, WorkKind.excel, WorkKind.pdf, WorkKind.txt}.contains(_kind);

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(
      type: _kind == WorkKind.unzip ? FileType.custom : FileType.any,
      allowedExtensions: _kind == WorkKind.unzip ? const ['zip'] : null,
    );
    if (picked.isEmpty) return;
    setState(() {
      if (_kind == WorkKind.unzip) _files.clear();
      _files.addAll(_kind == WorkKind.unzip ? picked.take(1) : picked);
    });
  }

  Future<void> _schedule() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: now,
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 30))));
    if (t == null) return;
    setState(() => _runAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _start() async {
    final task = _task.text.trim();
    if (WorkKind.needsTask(_kind) && task.isEmpty) {
      showJarvisSnack(context, 'Görevi yazın.', error: true);
      return;
    }
    if (WorkKind.needsSources(_kind) && _files.isEmpty) {
      showJarvisSnack(context, 'Kaynak dosya seçin.', error: true);
      return;
    }
    setState(() => _starting = true);
    try {
      final works = widget.controller.works;
      final id = works.newJobId();
      final sources = <WorkFile>[];
      for (final f in _files) {
        final bytes = await f.readAsBytes();
        if (bytes.length > 50 * 1024 * 1024) {
          throw StateError('${f.name} 50 MB sınırını aşıyor.');
        }
        sources.add(await WorkHub.storeSource(id, f.name, bytes));
      }
      await widget.controller.startWork(_kind, task, sources: sources, runAt: _runAt, id: id);
      if (mounted) {
        Navigator.pop(context);
        showJarvisSnack(context, _runAt == null ? 'İş başlatıldı' : 'İş zamanlandı');
      }
    } catch (e) {
      if (mounted) showJarvisSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yeni İş', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in WorkKind.all)
                  ChoiceChip(
                    avatar: Icon(workIcon(k), size: 16, color: _kind == k ? null : workColor(k)),
                    label: Text(WorkKind.label(k), style: const TextStyle(fontSize: 12)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() {
                      _kind = k;
                      if (!_allowsSources) _files.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _task,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: WorkKind.needsTask(_kind) ? 'Görev' : 'Not (isteğe bağlı)',
                hintText: WorkKind.hint(_kind),
                alignLabelWithHint: true,
              ),
            ),
            if (_allowsSources) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: Text(WorkKind.needsSources(_kind) ? 'Kaynak dosya seç' : 'Kaynak ekle (isteğe bağlı)'),
                ),
              ),
              if (_files.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final f in _files)
                      InputChip(
                        label: Text(f.name, style: const TextStyle(fontSize: 11.5)),
                        onDeleted: () => setState(() => _files.remove(f)),
                      ),
                  ],
                ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  child: TextButton.icon(
                  onPressed: _schedule,
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(_runAt == null
                      ? 'Hemen başlat (zamanla…)'
                      : 'Zaman: ${MaterialLocalizations.of(context).formatShortDate(_runAt!)} '
                          '${TimeOfDay.fromDateTime(_runAt!).format(context)}'),
                  ),
                ),
                if (_runAt != null)
                  IconButton(onPressed: () => setState(() => _runAt = null), icon: const Icon(Icons.close_rounded, size: 18)),
              ],
            ),
            if (_runAt != null)
               Text('Zamanlanan işler Ege açıkken (arka planda dahil) başlar.',
                  style: TextStyle(fontSize: 11.5, color: JColors.dim)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _starting ? null : _start,
                icon: _starting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(workIcon(_kind)),
                label: Text(_runAt == null ? '${WorkKind.label(_kind)} başlat' : 'Zamanla'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
