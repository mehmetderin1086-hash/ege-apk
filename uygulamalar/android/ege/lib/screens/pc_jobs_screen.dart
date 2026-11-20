import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pc_models.dart';
import '../state/jarvis_controller.dart';
import '../widgets/jarvis_ui.dart';
import 'pc_files_screen.dart';
import '../widgets/chat_palette.dart';

/// Coding agents (Claude Code / Codex), preset tasks and job history that run
/// on the Windows PC through the Ege PC Bridge.
class PcJobsScreen extends StatefulWidget {
  final JarvisController controller;
  final int initialTab;
  final String? initialCwd;
  final String? initialPrompt;

  const PcJobsScreen({
    super.key,
    required this.controller,
    this.initialTab = 0,
    this.initialCwd,
    this.initialPrompt,
  });

  @override
  State<PcJobsScreen> createState() => _PcJobsScreenState();
}

class _PcJobsScreenState extends State<PcJobsScreen> {
  final _prompt = TextEditingController();
  List<PcTask> _tasks = const [];
  bool _claude = false;
  bool _codex = false;
  String _agent = 'claude';
  String _mode = 'edit';
  String? _cwd;
  List<PcJob> _jobs = const [];
  bool _loading = true;
  bool _starting = false;
  String? _error;

  static const _ideas = [
    'Projede flutter analyze çalıştır ve çıkan uyarıları düzelt',
    'Bu projeye kısa bir README.md bölümü ekle: kurulum ve kullanım',
    'Kod tabanını incele ve en kritik 3 hatayı düzelt',
    'Ayarlar ekranına yeni bir seçenek ekle ve kaydedilmesini sağla',
    'Testleri çalıştır, kırılanları düzelt',
  ];

  List<PcRoot> get _roots => widget.controller.pcInfo?.roots ?? const [];

  @override
  void initState() {
    super.initState();
    _prompt.text = widget.initialPrompt ?? '';
    _cwd = widget.initialCwd ?? (_roots.isEmpty ? null : _roots.first.path);
    _load();
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = widget.controller.pcClient;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await client.tasks();
      final j = await client.jobs();
      if (!mounted) return;
      setState(() {
        _tasks = t.tasks;
        _claude = t.claude;
        _codex = t.codex;
        if (!_claude && _codex) _agent = 'codex';
        _jobs = j;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openJob(PcJob job) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PcJobScreen(controller: widget.controller, job: job)))
        .then((_) => _load());
  }

  Future<void> _startAgent() async {
    final cwd = _cwd;
    if (cwd == null || _prompt.text.trim().length < 4) {
      showJarvisSnack(context, 'Proje seçip görevi yazın.', error: true);
      return;
    }
    setState(() => _starting = true);
    try {
      final job = await widget.controller.pcClient!.startAgent(
        agent: _agent,
        prompt: _prompt.text.trim(),
        cwd: cwd,
        mode: _mode,
      );
      if (mounted) _openJob(job);
    } catch (e) {
      if (mounted) showJarvisSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _runTask(PcTask t) async {
    final cwd = _cwd;
    if (cwd == null) {
      showJarvisSnack(context, 'Önce proje seçin.', error: true);
      return;
    }
    try {
      final job = await widget.controller.pcClient!.runTask(t.id, cwd);
      if (mounted) _openJob(job);
    } catch (e) {
      if (mounted) showJarvisSnack(context, '$e', error: true);
    }
  }

  Widget _projectPicker() {
    final items = <DropdownMenuItem<String>>[
      for (final r in _roots) DropdownMenuItem(value: r.path, child: Text(r.name, overflow: TextOverflow.ellipsis)),
      if (_cwd != null && !_roots.any((r) => r.path == _cwd))
        DropdownMenuItem(
          value: _cwd,
          child: Text(_cwd!.split(RegExp(r'[\\/]')).last, overflow: TextOverflow.ellipsis),
        ),
    ];
    return DropdownButtonFormField<String>(
      key: ValueKey('cwd_$_cwd'),
      initialValue: _cwd,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Proje / klasör', isDense: true),
      items: items,
      onChanged: (v) => setState(() => _cwd = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PC Görevleri'),
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.smart_toy_rounded, size: 18), text: 'Ajan'),
            Tab(icon: Icon(Icons.play_circle_outline_rounded, size: 18), text: 'Görevler'),
            Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'İşler'),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style:  TextStyle(color: JColors.bad))))
                : TabBarView(children: [_agentTab(), _tasksTab(), _jobsTab()]),
      ),
    );
  }

  Widget _agentTab() {
    final none = !_claude && !_codex;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        GlassCard(
          glow: JColors.violet,
          child:  Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: JColors.violet),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Telefondan yaz, PC\'deki kodlama ajanı projede çalışsın. '
                  'Değişiklikler PC\'deki kaynak kodlara doğrudan uygulanır; bitince git farkını incele.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (none)
           Text('PC\'de Claude Code veya Codex CLI bulunamadı.', style: TextStyle(color: JColors.warn))
        else
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'claude', label: const Text('Claude Code'), icon: const Icon(Icons.psychology_rounded), enabled: _claude),
              ButtonSegment(value: 'codex', label: const Text('Codex'), icon: const Icon(Icons.terminal_rounded), enabled: _codex),
            ],
            selected: {_agent},
            onSelectionChanged: (s) => setState(() => _agent = s.first),
          ),
        const SizedBox(height: 12),
        _projectPicker(),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'edit', label: Text('Kodu düzenle'), icon: Icon(Icons.edit_note_rounded)),
            ButtonSegment(value: 'plan', label: Text('Sadece incele'), icon: Icon(Icons.visibility_rounded)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _prompt,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'Ajan için görev',
            hintText: 'Ör: Sohbet ekranına mesaj arama özelliği ekle ve testlerini yaz.',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final i in _ideas)
              ActionChip(label: Text(i, style: const TextStyle(fontSize: 11)), onPressed: () => setState(() => _prompt.text = i)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: JColors.violet),
            onPressed: none || _starting ? null : _startAgent,
            icon: _starting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.rocket_launch_rounded),
            label: Text(_starting ? 'Başlatılıyor…' : 'Ajanı Başlat'),
          ),
        ),
      ],
    );
  }

  Widget _tasksTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _projectPicker(),
        const SizedBox(height: 12),
        for (final t in _tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              glow: JColors.ok,
              onTap: () => _runTask(t),
              child: Row(
                children: [
                  Icon(_taskIcon(t.id), color: JColors.ok),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                   Icon(Icons.play_arrow_rounded, color: JColors.ok),
                ],
              ),
            ),
          ),
      ],
    );
  }

  IconData _taskIcon(String id) {
    if (id.startsWith('git')) return Icons.commit_rounded;
    if (id.contains('build')) return Icons.build_circle_rounded;
    if (id.contains('test')) return Icons.fact_check_rounded;
    if (id.contains('analyze')) return Icons.troubleshoot_rounded;
    return Icons.terminal_rounded;
  }

  Widget _jobsTab() {
    if (_jobs.isEmpty) {
      return  Center(child: Text('Henüz iş yok.', style: TextStyle(color: JColors.muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: _jobs.length,
        itemBuilder: (ctx, i) {
          final j = _jobs[i];
          return ListTile(
            leading: _JobStatusIcon(status: j.status),
            title: Text(j.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${j.cwd.split(RegExp(r'[\\/]')).last} • ${formatAgo(j.started)}',
                style:  TextStyle(fontSize: 11.5, color: JColors.dim)),
            trailing: Icon(j.kind == 'agent' ? Icons.smart_toy_rounded : Icons.terminal_rounded, size: 18, color: JColors.muted),
            onTap: () => _openJob(j),
          );
        },
      ),
    );
  }
}

class _JobStatusIcon extends StatelessWidget {
  final String status;

  const _JobStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      'running' => const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
      'done' =>  Icon(Icons.check_circle_rounded, color: JColors.ok),
      'cancelled' =>  Icon(Icons.cancel_rounded, color: JColors.warn),
      _ =>  Icon(Icons.error_rounded, color: JColors.bad),
    };
  }
}

/// Live output of a task / agent job (polled from the PC).
class PcJobScreen extends StatefulWidget {
  final JarvisController controller;
  final PcJob job;

  const PcJobScreen({super.key, required this.controller, required this.job});

  @override
  State<PcJobScreen> createState() => _PcJobScreenState();
}

class _PcJobScreenState extends State<PcJobScreen> {
  late PcJob _job = widget.job;
  final _out = StringBuffer();
  int _next = 0;
  Timer? _timer;
  final _scroll = ScrollController();
  bool _follow = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    final client = widget.controller.pcClient;
    if (client == null) return;
    try {
      final j = await client.job(_job.id, since: _next);
      if (!mounted) return;
      setState(() {
        _job = j;
        _next = j.next;
        _out.write(j.output);
        _error = null;
      });
      if (!j.running) _timer?.cancel();
      if (_follow && j.output.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = !_job.running;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_job.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              switch (_job.status) {
                'running' => 'Çalışıyor…',
                'done' => 'Tamamlandı',
                'cancelled' => 'İptal edildi',
                _ => 'Hata (çıkış ${_job.exitCode ?? '-'})',
              },
              style: TextStyle(
                fontSize: 11.5,
                color: _job.status == 'done' ? JColors.ok : _job.running ? JColors.accent : JColors.bad,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _follow ? 'Otomatik kaydırma açık' : 'Otomatik kaydırma kapalı',
            onPressed: () => setState(() => _follow = !_follow),
            icon: Icon(_follow ? Icons.vertical_align_bottom_rounded : Icons.pause_rounded),
          ),
          IconButton(
            tooltip: 'Kopyala',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _out.toString()));
              showJarvisSnack(context, 'Çıktı kopyalandı');
            },
            icon: const Icon(Icons.copy_rounded),
          ),
          if (_job.running)
            IconButton(
              tooltip: 'İptal et',
              onPressed: () async {
                try {
                  final j = await widget.controller.pcClient!.cancelJob(_job.id);
                  if (mounted) setState(() => _job = j);
                } catch (e) {
                  if (context.mounted) showJarvisSnack(context, '$e', error: true);
                }
              },
              icon:  Icon(Icons.stop_circle_rounded, color: JColors.bad),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_job.running) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF3F1219),
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(fontSize: 12)),
            ),
          Expanded(
            child: Container(
              color: JColors.code,
              width: double.infinity,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 30),
                child: SelectableText(
                  _out.isEmpty ? 'Çıktı bekleniyor…' : _out.toString(),
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.4, color: ChatPalette.muted),
                ),
              ),
            ),
          ),
          if (done)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PcGitScreen(controller: widget.controller, path: _job.cwd, initialTab: 1),
                        )),
                        icon: const Icon(Icons.difference_rounded),
                        label: const Text('Değişiklikleri gör (git)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PcFilesScreen(
                            controller: widget.controller,
                            startPath: _job.cwd,
                            title: _job.cwd.split(RegExp(r'[\\/]')).last,
                          ),
                        )),
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Dosyalar'),
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
