import 'package:flutter/material.dart';

import '../services/agent_core.dart';
import '../state/jarvis_controller.dart';
import '../widgets/jarvis_ui.dart';

const _skillTemplate = '---\n'
    'name: yeni-beceri\n'
    'description: …\n'
    'version: 1.0.0\n'
    'metadata:\n'
    '  hermes:\n'
    '    category: genel\n'
    '    tags: []\n'
    '---\n\n'
    '## Ne zaman\n\n'
    '## Yöntem\n'
    '1. \n\n'
    '## Tuzaklar\n\n'
    '## Doğrulama\n';

/// Hermes Agent özellikleri: hafıza, beceriler, zamanlı görevler, kişilik,
/// geçmiş arama ve araç günlüğü.
class AgentCenterScreen extends StatelessWidget {
  final JarvisController controller;

  const AgentCenterScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title:  Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ajan Merkezi'),
              Text('Hermes Agent özellikleri', style: TextStyle(fontSize: 11.5, color: JColors.muted)),
            ],
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Hafıza'),
              Tab(text: 'Beceriler'),
              Tab(text: 'Görevler'),
              Tab(text: 'Kişilik'),
              Tab(text: 'Arama'),
              Tab(text: 'Araçlar'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MemoryTab(c: controller),
            _SkillsTab(c: controller),
            _CronTab(c: controller),
            _PersonaTab(c: controller),
            _SearchTab(c: controller),
            _ToolsTab(c: controller),
          ],
        ),
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(14, 12, 14, 30);

// ------------------------------------------------------------------ HAFIZA

class _MemoryTab extends StatefulWidget {
  final JarvisController c;
  const _MemoryTab({required this.c});

  @override
  State<_MemoryTab> createState() => _MemoryTabState();
}

class _MemoryTabState extends State<_MemoryTab> with AutomaticKeepAliveClientMixin {
  late final _mem = TextEditingController(text: widget.c.settings.memoryText);
  late final _user = TextEditingController(text: widget.c.settings.userProfile);

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _mem.dispose();
    _user.dispose();
    super.dispose();
  }

  Future<void> _save(bool isMemory) async {
    final c = widget.c;
    final s = c.settings;
    final text = (isMemory ? _mem.text : _user.text).trim();
    final limit = isMemory ? AgentMemoryLimits.memory : AgentMemoryLimits.user;
    if (text.length > limit) {
      showJarvisSnack(context,
          '${isMemory ? 'MEMORY' : 'USER'} en fazla $limit karakter olabilir (şu an ${text.length}). Kaydedilmedi.');
      return;
    }
    await c.backupMemoryText(text: isMemory ? s.memoryText : s.userProfile, isUser: !isMemory);
    await c.updateSettings(isMemory
        ? s.copyWith(memoryText: text)
        : s.copyWith(userProfile: text));
    if (mounted) showJarvisSnack(context, isMemory ? 'MEMORY kaydedildi' : 'USER kaydedildi');
  }

  Widget _card(String label, TextEditingController ctrl, int limit, bool isMemory, Color glow, String hint) {
    return GlassCard(
      glow: glow,
      child: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final n = ctrl.text.trim().length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(memoryHeader(label, ctrl.text, limit),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (n / limit).clamp(0.0, 1.0),
                minHeight: 4,
                color: n > limit ? JColors.bad : (n > limit * 0.85 ? JColors.warn : glow),
              ),
              const SizedBox(height: 4),
              Text(hint, style:  TextStyle(fontSize: 11.5, color: JColors.muted)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                minLines: 4,
                maxLines: 10,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _save(isMemory),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Kaydet'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: _pad,
      children: [
        _card('MEMORY', _mem, AgentMemoryLimits.memory, true, JColors.ok,
            'Ortam, proje ve ders notları. Her satır "- …" ile başlar.'),
        const SizedBox(height: 12),
        _card('USER', _user, AgentMemoryLimits.user, false, JColors.violet,
            'Sizin hakkınızda: tercihler, yanıt biçimi, alışkanlıklar.'),
      ],
    );
  }
}

// ------------------------------------------------------------------ BECERİLER

class _SkillsTab extends StatelessWidget {
  final JarvisController c;
  const _SkillsTab({required this.c});

  Future<void> _edit(BuildContext context, String md, {AgentSkill? skill}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JColors.surface,
      showDragHandle: true,
      builder: (ctx) => _SkillSheet(c: c, markdown: md, skill: skill),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final skills = c.skillStore.sorted;
        return ListView(
          padding: _pad,
          children: [
            Row(
              children: [
                const Expanded(child: SectionTitle('Beceriler', icon: Icons.auto_awesome_rounded)),
                FilledButton.icon(
                  onPressed: () => _edit(context, _skillTemplate),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Yeni beceri'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (skills.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Henüz beceri yok.')),
            for (final s in skills)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  onTap: () => _edit(context, s.toMarkdown(), skill: s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        Pill('v${s.version}', color: JColors.violet),
                        Pill(s.category, color: JColors.primary),
                        Pill('${s.uses} kullanım', color: JColors.ok),
                        if (s.builtIn)  Pill('yerleşik', color: JColors.warn),
                      ]),
                      const SizedBox(height: 6),
                      Text(s.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:  TextStyle(fontSize: 12.5, color: JColors.muted)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SkillSheet extends StatefulWidget {
  final JarvisController c;
  final String markdown;
  final AgentSkill? skill;
  const _SkillSheet({required this.c, required this.markdown, this.skill});

  @override
  State<_SkillSheet> createState() => _SkillSheetState();
}

class _SkillSheetState extends State<_SkillSheet> {
  late final _ctrl = TextEditingController(text: widget.markdown);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nav = Navigator.of(context);
    final msg = await widget.c.skillStore.saveMarkdown(_ctrl.text);
    widget.c.notifyChanged();
    if (!mounted) return;
    if (msg.startsWith('Kaydedildi')) nav.pop();
    showJarvisSnack(context, msg);
  }

  Future<void> _delete() async {
    final s = widget.skill!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Beceri silinsin mi?'),
        content: Text(s.builtIn
            ? '"${s.name}" yerleşik bir beceri. Yine de silmek istiyor musunuz?'
            : '"${s.name}" kalıcı olarak silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    final msg = await widget.c.skillStore.manage(action: 'delete', name: s.name);
    widget.c.notifyChanged();
    if (!mounted) return;
    nav.pop();
    showJarvisSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, MediaQuery.of(context).viewInsets.bottom + 14),
      child: SizedBox(
        height: h * 0.7,
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                decoration: const InputDecoration(
                  labelText: 'SKILL.md',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.skill != null)
                  TextButton.icon(
                    onPressed: _delete,
                    icon:  Icon(Icons.delete_outline_rounded, size: 18, color: JColors.bad),
                    label:  Text('Sil', style: TextStyle(color: JColors.bad)),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Kaydet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ GÖREVLER

String _fmtDt(DateTime t) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(t.day)}.${p(t.month)} ${p(t.hour)}:${p(t.minute)}';
}

class _CronTab extends StatelessWidget {
  final JarvisController c;
  const _CronTab({required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final jobs = c.cronStore.jobs;
        return ListView(
          padding: _pad,
          children: [
            Row(
              children: [
                const Expanded(child: SectionTitle('Zamanlı görevler', icon: Icons.schedule_rounded)),
                FilledButton.icon(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: JColors.surface,
                    showDragHandle: true,
                    builder: (_) => _CronForm(c: c),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Yeni görev'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (jobs.isEmpty)
               Padding(
                padding: EdgeInsets.all(20),
                child: Text('Henüz zamanlı görev yok.', style: TextStyle(color: JColors.muted)),
              ),
            for (final j in jobs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  glow: j.enabled ? JColors.primary : JColors.dim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(j.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                          ),
                          Switch(value: j.enabled, onChanged: (v) => c.setCronEnabled(j.id, v)),
                        ],
                      ),
                      Text(j.parsed?.describe() ?? j.schedule,
                          style:  TextStyle(fontSize: 12.5, color: JColors.accent)),
                      Text(
                        'Sonraki: ${j.nextRun == null ? '-' : _fmtDt(j.nextRun!)} • ${j.runs} kez çalıştı'
                        '${j.speak ? ' • sesli' : ''}',
                        style:  TextStyle(fontSize: 11.5, color: JColors.muted),
                      ),
                      if (j.lastOutput.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Son çıktı${j.lastRun == null ? '' : ' (${_fmtDt(j.lastRun!)})'}: '
                          '${j.lastOutput.replaceAll('\n', ' ')}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:  TextStyle(fontSize: 12, color: JColors.text),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: c.runningCron.contains(j.id)
                                ? null
                                : () async {
                                    final out = await c.runCronJob(j.id, manual: true);
                                    if (context.mounted) {
                                      showJarvisSnack(context, out.length > 160 ? '${out.substring(0, 160)}…' : out);
                                    }
                                  },
                            icon: c.runningCron.contains(j.id)
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.play_arrow_rounded, size: 18),
                            label: const Text('Çalıştır'),
                          ),
                          TextButton.icon(
                            onPressed: () => c.removeCron(j.id),
                            icon:  Icon(Icons.delete_outline_rounded, size: 18, color: JColors.bad),
                            label:  Text('Sil', style: TextStyle(color: JColors.bad)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CronForm extends StatefulWidget {
  final JarvisController c;
  const _CronForm({required this.c});

  @override
  State<_CronForm> createState() => _CronFormState();
}

class _CronFormState extends State<_CronForm> {
  final _name = TextEditingController();
  final _prompt = TextEditingController();
  final _when = TextEditingController();
  bool _speak = false;
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _when.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final before = widget.c.cronStore.jobs.length;
    setState(() => _busy = true);
    final msg = await widget.c.createCron(
      name: _name.text,
      prompt: _prompt.text,
      schedule: _when.text,
      speak: _speak,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.c.cronStore.jobs.length > before) {
      final nav = Navigator.of(context);
      nav.pop();
      showJarvisSnack(context, msg);
    } else {
      setState(() => _msg = msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Yeni görev', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            key: const Key('cron_name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Ad', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('cron_prompt'),
            controller: _prompt,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'Ne yapılsın', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('cron_when'),
            controller: _when,
            decoration: const InputDecoration(
              labelText: 'Zaman',
              helperText: 'Örn: "her gün 08:00", "hafta içi 9\'da", "her pazartesi 10:00", '
                  '"30 dakika sonra", "her 2 saatte"',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sesli oku'),
            value: _speak,
            onChanged: (v) => setState(() => _speak = v),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_msg!, style:  TextStyle(color: JColors.warn, fontSize: 12.5)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _create,
              child: const Text('Oluştur'),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ KİŞİLİK

class _PersonaTab extends StatefulWidget {
  final JarvisController c;
  const _PersonaTab({required this.c});

  @override
  State<_PersonaTab> createState() => _PersonaTabState();
}

class _PersonaTabState extends State<_PersonaTab> {
  late final _soul = TextEditingController(text: widget.c.settings.personaPrompt);

  @override
  void dispose() {
    _soul.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.settings;
        return ListView(
          padding: _pad,
          children: [
            const SectionTitle('Kişilik', icon: Icons.face_rounded),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: RadioGroup<String>(
                groupValue: s.personality,
                onChanged: (v) {
                  if (v != null) c.updateSettings(s.copyWith(personality: v));
                },
                child: Column(
                  children: [
                    for (final p in Personalities.all)
                      RadioListTile<String>(
                        value: p.id,
                        dense: true,
                        title: Text(p.label),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              glow: JColors.violet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SOUL (temel kişilik metni)', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _soul,
                    minLines: 4,
                    maxLines: 10,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await c.updateSettings(c.settings.copyWith(personaPrompt: _soul.text.trim()));
                        if (context.mounted) showJarvisSnack(context, 'SOUL kaydedildi');
                      },
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Öğrenme döngüsü'),
                    subtitle: const Text('Sohbetlerden hafıza ve beceri öğrenir.', style: TextStyle(fontSize: 12)),
                    value: s.learningLoop,
                    onChanged: (v) => c.updateSettings(s.copyWith(learningLoop: v)),
                  ),
                  SwitchListTile(
                    title: const Text('Sessiz saatler (23:00-07:00)'),
                    subtitle: const Text('Bu aralıkta görevler sesli çalışmaz.', style: TextStyle(fontSize: 12)),
                    value: s.quietHours,
                    onChanged: (v) => c.updateSettings(s.copyWith(quietHours: v)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------ ARAMA

class _SearchTab extends StatefulWidget {
  final JarvisController c;
  const _SearchTab({required this.c});

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final _q = TextEditingController();
  List<SessionHit> _hits = const [];
  bool _searched = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _run() => setState(() {
        _hits = searchSessions(widget.c.sessions, _q.text);
        _searched = true;
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListView(
      padding: _pad,
      children: [
        TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            labelText: 'Geçmiş sohbetlerde ara',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(onPressed: _run, icon: const Icon(Icons.search_rounded)),
          ),
        ),
        const SizedBox(height: 10),
        if (_searched && _hits.isEmpty)
           Padding(
            padding: EdgeInsets.all(20),
            child: Text('Sonuç bulunamadı.', style: TextStyle(color: JColors.muted)),
          ),
        for (final h in _hits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              onTap: () {
                c.selectSession(h.sessionId);
                c.openTab(0);
                Navigator.pop(context);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.sessionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  Text('${h.role == 'user' ? 'Siz' : 'Ege'} • ${formatAgo(h.at)}',
                      style:  TextStyle(fontSize: 11.5, color: JColors.accent)),
                  const SizedBox(height: 4),
                  Text(h.snippet,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style:  TextStyle(fontSize: 12.5, color: JColors.muted)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ ARAÇLAR

class _ToolsTab extends StatelessWidget {
  final JarvisController c;
  const _ToolsTab({required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final todos = c.todos[c.activeSessionId] ?? const <TodoItem>[];
        String p(int v) => v.toString().padLeft(2, '0');
        return ListView(
          padding: _pad,
          children: [
            if (todos.isNotEmpty) ...[
              const SectionTitle('Görev listesi', icon: Icons.checklist_rounded),
              GlassCard(
                glow: JColors.ok,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < todos.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('${i + 1}. ${todos[i].icon} ${todos[i].text}', style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SectionTitle('Araç günlüğü', icon: Icons.build_circle_outlined),
            if (c.toolLog.isEmpty)
               Padding(
                padding: EdgeInsets.all(20),
                child: Text('Henüz araç çağrısı yok.', style: TextStyle(color: JColors.muted)),
              ),
            for (final t in c.toolLog)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GlassCard(
                  glow: t.ok ? JColors.ok : JColors.bad,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.ok ? '✓' : '✗',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, color: t.ok ? JColors.ok : JColors.bad)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.tool, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            if (t.detail.isNotEmpty)
                              Text(t.detail,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:  TextStyle(fontSize: 12, color: JColors.muted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${p(t.at.hour)}:${p(t.at.minute)}',
                              style:  TextStyle(fontSize: 11.5, color: JColors.muted)),
                          Text('${(t.ms / 1000).toStringAsFixed(1)} sn',
                              style:  TextStyle(fontSize: 11.5, color: JColors.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
