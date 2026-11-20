import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/jarvis_models.dart';
import '../services/math_evaluator.dart';
import '../state/jarvis_controller.dart';
import '../widgets/device_controls.dart';
import '../widgets/markdown_message.dart';
import 'web_tools_screen.dart';
import '../widgets/chat_palette.dart';

class ToolsScreen extends StatefulWidget {
  final JarvisController controller;

  const ToolsScreen({super.key, required this.controller});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.controller.toolsSubTabIndex.clamp(0, 5),
    );
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging &&
          widget.controller.toolsSubTabIndex != _tabCtrl.index) {
        widget.controller.toolsSubTabIndex = _tabCtrl.index;
      }
    });
  }

  @override
  void didUpdateWidget(covariant ToolsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final desired = widget.controller.toolsSubTabIndex.clamp(0, 5);
    if (_tabCtrl.index != desired) {
      _tabCtrl.animateTo(desired);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desired = widget.controller.toolsSubTabIndex.clamp(0, 5);
    if (_tabCtrl.index != desired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabCtrl.index != desired) {
          _tabCtrl.animateTo(desired);
        }
      });
    }

    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: ChatPalette.background,
            border: Border(bottom: BorderSide(color: ChatPalette.border)),
          ),
          child: TabBar(
            dividerColor: Colors.transparent,
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: ChatPalette.accent,
            labelColor: ChatPalette.accent,
            unselectedLabelColor: ChatPalette.muted,
            tabs: const [
              Tab(icon: Icon(Icons.timer_outlined, size: 18), text: 'Sayaçlar'),
              Tab(icon: Icon(Icons.edit_note_rounded, size: 19), text: 'Notlar'),
              Tab(
                icon: Icon(Icons.calculate_outlined, size: 18),
                text: 'Hesap Makinesi',
              ),
              Tab(icon: Icon(Icons.memory_rounded, size: 18), text: 'Cihaz'),
              Tab(icon: Icon(Icons.travel_explore_rounded, size: 18), text: 'Web'),
              Tab(icon: Icon(Icons.download_rounded, size: 18), text: 'İndir'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _TimersTab(controller: widget.controller),
              _NotesTab(controller: widget.controller),
              _CalculatorTab(controller: widget.controller),
              _DeviceMonitorTab(controller: widget.controller),
              WebScraperTab(controller: widget.controller),
              DownloadsTab(controller: widget.controller),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimersTab extends StatelessWidget {
  final JarvisController controller;

  const _TimersTab({required this.controller});

  Future<void> _showCustomTimerDialog(BuildContext context) async {
    final labelCtrl = TextEditingController(text: 'Hatırlatma');
    final minCtrl = TextEditingController(text: '5');
    final secCtrl = TextEditingController(text: '0');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ChatPalette.surface,
        title: const Text('Özel Zamanlayıcı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Etiket'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Dakika'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: secCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Saniye'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Başlat'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final m = int.tryParse(minCtrl.text.trim()) ?? 0;
      final s = int.tryParse(secCtrl.text.trim()) ?? 0;
      final total = m * 60 + s;
      if (total > 0) {
        await controller.addTimer(total, labelCtrl.text.trim());
      }
    }
    labelCtrl.dispose();
    minCtrl.dispose();
    secCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timers = controller.timers;
    final now = controller.nowEpoch;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _QuickTimerBtn(
              label: '+1 dk',
              onTap: () => controller.addTimer(60, '1 Dakika'),
            ),
            _QuickTimerBtn(
              label: '+5 dk Çay',
              onTap: () => controller.addTimer(300, 'Çay'),
            ),
            _QuickTimerBtn(
              label: '+10 dk',
              onTap: () => controller.addTimer(600, '10 Dakika'),
            ),
            _QuickTimerBtn(
              label: '+25 dk Pomodoro',
              onTap: () => controller.addTimer(1500, 'Pomodoro'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: ChatPalette.accent,
                foregroundColor: const Color(0xFF030712),
              ),
              onPressed: () => _showCustomTimerDialog(context),
              icon: const Icon(Icons.add_alarm_rounded, size: 18),
              label: const Text('Özel Kur'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (timers.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: ChatPalette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ChatPalette.border),
            ),
            child: Column(
              children: [
                Icon(Icons.hourglass_empty_rounded,
                    size: 36, color: ChatPalette.muted),
                SizedBox(height: 8),
                Text(
                  'Henüz aktif zamanlayıcı yok.\nSohbette "5 dakika çay sayacı kur" da diyebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ChatPalette.muted, fontSize: 13.5),
                ),
              ],
            ),
          )
        else
          for (final t in timers) ...[
            _TimerCard(
              timer: t,
              nowEpoch: now,
              onAcknowledge: () => controller.acknowledgeTimer(t.id),
              onDelete: () => controller.removeTimerById(t.id),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _QuickTimerBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickTimerBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: ChatPalette.ink,
        side: BorderSide(color: ChatPalette.border),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}

class _TimerCard extends StatelessWidget {
  final JarvisTimer timer;
  final int nowEpoch;
  final VoidCallback onAcknowledge;
  final VoidCallback onDelete;

  const _TimerCard({
    required this.timer,
    required this.nowEpoch,
    required this.onAcknowledge,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final rem = timer.remainingSec(nowEpoch);
    final progress = timer.durationSec > 0
        ? (1.0 - (rem / timer.durationSec)).clamp(0.0, 1.0)
        : 1.0;
    final mins = rem ~/ 60;
    final secs = rem % 60;
    final clock =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    final isRinging = timer.fired && !timer.acknowledged;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRinging ? const Color(0xFF2B1222) : ChatPalette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRinging ? const Color(0xFFF43F5E) : ChatPalette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRinging
                    ? Icons.notifications_active_rounded
                    : Icons.timer_outlined,
                color: isRinging
                    ? const Color(0xFFFB7185)
                    : ChatPalette.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  timer.label,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                timer.fired ? 'DOLDU' : clock,
                style: TextStyle(
                  fontSize: 18,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: isRinging
                      ? const Color(0xFFFDA4AF)
                      : ChatPalette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: timer.fired ? 1.0 : progress,
            backgroundColor: ChatPalette.soft,
            color: isRinging
                ? const Color(0xFFF43F5E)
                : ChatPalette.accent,
            minHeight: 5,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isRinging)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onAcknowledge,
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: const Text('Sustur / Tamam'),
                ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Sil'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotesTab extends StatefulWidget {
  final JarvisController controller;

  const _NotesTab({required this.controller});

  @override
  State<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<_NotesTab> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  String _boundNoteId = '';
  bool _summarizing = false;

  @override
  void initState() {
    super.initState();
    final note = widget.controller.activeNote;
    _boundNoteId = note.id;
    _titleCtrl = TextEditingController(text: note.title);
    _bodyCtrl = TextEditingController(text: note.content);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _syncFromModelIfNeeded() {
    final note = widget.controller.activeNote;
    if (note.id != _boundNoteId) {
      _boundNoteId = note.id;
      _titleCtrl.text = note.title;
      _bodyCtrl.text = note.content;
    } else if (_bodyCtrl.text != note.content &&
        !FocusScope.of(context).hasFocus) {
      _bodyCtrl.text = note.content;
    }
  }

  Future<void> _summarize() async {
    setState(() => _summarizing = true);
    final res = await widget.controller.summarizeActiveNoteWithAi();
    if (!mounted) return;
    setState(() => _summarizing = false);

    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.text)),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ChatPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Not Özeti',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ChatPalette.accent,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  child: MarkdownMessage(text: res.text),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: res.text));
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Kopyala & Kapat'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final next =
                          '${_bodyCtrl.text.trimRight()}\n\n--- AI Özeti ---\n${res.text}';
                      _bodyCtrl.text = next;
                      await widget.controller.updateActiveNote(content: next);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Notun Sonuna Ekle'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncFromModelIfNeeded();
    final c = widget.controller;
    final note = c.activeNote;
    final words = _bodyCtrl.text.trim().isEmpty
        ? 0
        : _bodyCtrl.text.trim().split(RegExp(r'\s+')).length;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final n in c.notes)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      selected: n.id == note.id,
                      label: Text(n.title.isEmpty ? 'Adsız' : n.title),
                      onSelected: (_) => c.selectNote(n.id),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 17),
                  label: const Text('Yeni Not'),
                  onPressed: () => c.createNote(
                    title: 'Not ${c.notes.length + 1}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleCtrl,
                  onChanged: (v) => c.updateActiveNote(title: v),
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Not Başlığı',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Paylaş',
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text: '${_titleCtrl.text}\n\n${_bodyCtrl.text}',
                    title: _titleCtrl.text,
                  ),
                ),
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                tooltip: 'Notu sil',
                onPressed: () => c.deleteNote(note.id),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFFB7185),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              controller: _bodyCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (v) => c.updateActiveNote(content: v),
              style: TextStyle(
                color: ChatPalette.ink,
                fontSize: 14.5,
                height: 1.45,
              ),
              decoration: const InputDecoration(
                hintText: 'Notlarını buraya yaz (otomatik kaydedilir)...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$words kelime • ${_bodyCtrl.text.length} karakter',
                style: TextStyle(color: ChatPalette.muted, fontSize: 12),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ChatPalette.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _summarizing ? null : _summarize,
                icon: _summarizing
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 17),
                label: const Text('AI ile Özetle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalculatorTab extends StatefulWidget {
  final JarvisController controller;

  const _CalculatorTab({required this.controller});

  @override
  State<_CalculatorTab> createState() => _CalculatorTabState();
}

class _CalculatorTabState extends State<_CalculatorTab> {
  String _expr = '';
  String _output = '0';
  String? _error;

  void _append(String tok) {
    setState(() {
      _error = null;
      _expr += tok;
      _tryLiveEval();
    });
  }

  void _tryLiveEval() {
    if (_expr.trim().isEmpty) {
      _output = '0';
      return;
    }
    try {
      final res = MathEvaluator.evaluate(_expr);
      _output = MathEvaluator.formatResult(res);
    } catch (_) {
      // Partial expression while typing
    }
  }

  void _evaluateFinal() {
    if (_expr.trim().isEmpty) return;
    try {
      final val = MathEvaluator.evaluate(_expr);
      final formatted = MathEvaluator.formatResult(val);
      widget.controller.addCalcHistory(_expr, formatted);
      setState(() {
        _output = formatted;
        _expr = formatted;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  void _backspace() {
    if (_expr.isEmpty) return;
    setState(() {
      _error = null;
      _expr = _expr.substring(0, _expr.length - 1);
      _tryLiveEval();
    });
  }

  void _clear() {
    setState(() {
      _expr = '';
      _output = '0';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sciKeys = const ['(', ')', '^', 'sqrt(', 'sin(', 'cos(', 'ln(', 'pi'];
    final gridKeys = const [
      '7', '8', '9', '/',
      '4', '5', '6', '*',
      '1', '2', '3', '-',
      '0', '.', '=', '+',
    ];

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ChatPalette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ChatPalette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Text(
                  _expr.isEmpty ? '0' : _expr,
                  style: TextStyle(
                    fontSize: 20,
                    fontFamily: 'monospace',
                    color: ChatPalette.ink,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error ?? _output,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _error != null ? 14 : 30,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: _error != null
                      ? const Color(0xFFFB7185)
                      : ChatPalette.accent,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clear,
                  child: const Text('C'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: _backspace,
                  child: const Icon(Icons.backspace_outlined, size: 18),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: _output),
                  ),
                  child: const Text('Kopyala'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in sciKeys)
                InkWell(
                  onTap: () => _append(k),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: ChatPalette.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ChatPalette.border),
                    ),
                    child: Text(
                      k,
                      style: TextStyle(
                        color: ChatPalette.accent,
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 2.0,
              ),
              itemCount: gridKeys.length,
              itemBuilder: (context, idx) {
                final key = gridKeys[idx];
                final isEquals = key == '=';
                final isOp = const ['/', '*', '-', '+'].contains(key);
                return FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isEquals
                        ? ChatPalette.accent
                        : (isOp
                            ? const Color(0xFF132A46)
                            : ChatPalette.surface),
                    foregroundColor:
                        isEquals ? const Color(0xFF030712) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    if (isEquals) {
                      _evaluateFinal();
                    } else {
                      _append(key);
                    }
                  },
                  child: Text(
                    key,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.controller.calcHistory.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              scrollDirection: Axis.horizontal,
              itemCount: widget.controller.calcHistory.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, idx) {
                final h = widget.controller.calcHistory[idx];
                return ActionChip(
                  label: Text(
                    '${h.expr} = ${h.result}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () {
                    setState(() {
                      _expr = h.expr;
                      _output = h.result;
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DeviceMonitorTab extends StatelessWidget {
  final JarvisController controller;

  const _DeviceMonitorTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    final m = controller.deviceMetrics;
    final ramFrac = m.totalRamMb > 0
        ? (m.usedRamMb / m.totalRamMb).clamp(0.0, 1.0)
        : 0.0;
    final usedStorageGb = (m.totalStorageGb - m.freeStorageGb).clamp(
      0.0,
      m.totalStorageGb,
    );
    final storageFrac = m.totalStorageGb > 0
        ? (usedStorageGb / m.totalStorageGb).clamp(0.0, 1.0)
        : 0.0;
    final batFrac = m.batteryPct >= 0
        ? (m.batteryPct / 100.0).clamp(0.0, 1.0)
        : 0.0;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ChatPalette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ChatPalette.border),
          ),
          child: Row(
            children: [
              Icon(Icons.phone_android_rounded,
                  size: 32, color: ChatPalette.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${m.manufacturer} ${m.model}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Android ${m.androidVersion} (SDK ${m.sdkInt}) • Ağ: ${m.networkType}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ChatPalette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Yenile',
                onPressed: controller.refreshDeviceMetrics,
                icon: Icon(Icons.refresh_rounded, color: ChatPalette.accent),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _MetricBarCard(
          icon: m.charging ? Icons.battery_charging_full : Icons.battery_std,
          title: 'Batarya',
          valueText: m.batteryPct >= 0
              ? '%${m.batteryPct}${m.charging ? ' (Şarj oluyor)' : ''}'
              : 'Okunamadı',
          fraction: batFrac,
          color: m.batteryPct < 20
              ? const Color(0xFFF43F5E)
              : const Color(0xFF34D399),
        ),
        const SizedBox(height: 10),
        _MetricBarCard(
          icon: Icons.memory_rounded,
          title: 'RAM Kullanımı',
          valueText: '${m.usedRamMb} / ${m.totalRamMb} MB',
          fraction: ramFrac,
          color: ChatPalette.accent,
        ),
        const SizedBox(height: 10),
        _MetricBarCard(
          icon: Icons.storage_rounded,
          title: 'Dahili Depolama',
          valueText:
              '${m.freeStorageGb.toStringAsFixed(1)} GB boş / ${m.totalStorageGb.toStringAsFixed(1)} GB toplam',
          fraction: storageFrac,
          color: const Color(0xFFA78BFA),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Telefon Denetim Merkezi',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    controller.torchOn
                        ? Icons.flashlight_on_rounded
                        : Icons.flashlight_off_rounded,
                  ),
                  title: const Text('El Feneri'),
                  subtitle: Text(controller.torchOn ? 'Açık' : 'Kapalı'),
                  value: controller.torchOn,
                  onChanged: (val) => controller.toggleFlashlight(val),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.volume_up_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: controller.mediaVolumePct.toDouble().clamp(0, 100),
                        min: 0,
                        max: 100,
                        divisions: 20,
                        label: '%${controller.mediaVolumePct}',
                        onChanged: (v) => controller.setMediaVolume(v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '%${controller.mediaVolumePct}',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.skip_previous_rounded, size: 18),
                      label: const Text('Önceki'),
                      onPressed: () => controller.controlMedia('previous'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Oynat/Duraklat'),
                      onPressed: () => controller.controlMedia('play_pause'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.skip_next_rounded, size: 18),
                      label: const Text('Sonraki'),
                      onPressed: () => controller.controlMedia('next'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.alarm_add_rounded, size: 18),
                      label: const Text('Sistem Alarmı Kur'),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (picked != null) {
                          await controller.setSystemAlarm(
                            picked.hour,
                            picked.minute,
                            'Ege Alarmı',
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Sistem Ayarları Kısayolları',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final item in const [
                      ('Wi-Fi', 'wifi', Icons.wifi_rounded),
                      ('Bluetooth', 'bluetooth', Icons.bluetooth_rounded),
                      ('Konum', 'location', Icons.location_on_rounded),
                      ('Ekran', 'display', Icons.brightness_6_rounded),
                      ('Ses', 'sound', Icons.music_note_rounded),
                      ('Pil', 'battery', Icons.battery_charging_full_rounded),
                      ('Uygulamalar', 'apps', Icons.apps_rounded),
                    ])
                      ActionChip(
                        avatar: Icon(item.$3, size: 16),
                        label: Text(item.$1),
                        onPressed: () => controller.openSystemSettings(item.$2),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const QuickSystemControlsCard(),
        const SizedBox(height: 12),
        InstalledAppsManager(controller: controller),
        const SizedBox(height: 12),
        const AppUsageCard(),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: () {
            controller.sendMessage('Cihaz ve batarya durumumu özetle');
            controller.openTab(0);
          },
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('Sohbete Özet Rapor Gönder (Çevrimdışı)'),
        ),
      ],
    );
  }
}

class _MetricBarCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String valueText;
  final double fraction;
  final Color color;

  const _MetricBarCard({
    required this.icon,
    required this.title,
    required this.valueText,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ChatPalette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ChatPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                valueText,
                style: TextStyle(color: color, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: fraction,
            minHeight: 7,
            backgroundColor: ChatPalette.soft,
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}
