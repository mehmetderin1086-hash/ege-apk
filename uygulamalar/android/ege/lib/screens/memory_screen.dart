import 'package:flutter/material.dart';

import '../services/agent_core.dart';
import '../state/jarvis_controller.dart';
import '../widgets/jarvis_ui.dart';

/// Persistent memory editor (Windows Ege "Hafıza" / Tercihler.md port).
class MemoryScreen extends StatefulWidget {
  final JarvisController controller;

  const MemoryScreen({super.key, required this.controller});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _add = TextEditingController();
  bool _raw = false;
  late final TextEditingController _rawCtrl = TextEditingController(
    text: widget.controller.settings.memoryText,
  );

  JarvisController get c => widget.controller;

  @override
  void dispose() {
    _add.dispose();
    _rawCtrl.dispose();
    super.dispose();
  }

  Future<void> _addFact() async {
    final msg = await c.addMemory(_add.text);
    _add.clear();
    if (mounted) showJarvisSnack(context, msg);
  }

  Future<void> _removeLine(String line) async {
    final rest = c.memoryItems.where((l) => l != line).join('\n');
    await c.setMemoryText(rest);
  }

  Future<void> _backups() async {
    final list = await c.memoryBackups();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: list.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Henüz yedek yok.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Önceki sürümler',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  for (final b in list)
                    ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: Text(formatAgo(b.at)),
                      subtitle: Text(
                        b.text.replaceAll('\n', ' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          await c.setMemoryText(b.text);
                          _rawCtrl.text = b.text;
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            showJarvisSnack(context, 'Hafıza geri yüklendi');
                          }
                        },
                        child: const Text('Geri yükle'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final items = c.memoryItems;
        final chars = c.settings.memoryText.length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Hafıza'),
            actions: [
              IconButton(
                tooltip: 'Yedekler',
                onPressed: _backups,
                icon: const Icon(Icons.history_rounded),
              ),
              IconButton(
                tooltip: _raw ? 'Liste görünümü' : 'Metin olarak düzenle',
                onPressed: () => setState(() {
                  _raw = !_raw;
                  _rawCtrl.text = c.settings.memoryText;
                }),
                icon: Icon(_raw ? Icons.list_rounded : Icons.edit_note_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
            children: [
              GlassCard(
                glow: JColors.ok,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Hafıza açık',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Kayıtlı bilgiler her sohbette yapay zekâya arka plan bilgisi olarak verilir; '
                        'işlem yetkisi vermez.',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: c.settings.memoryEnabled,
                      onChanged: (v) => c.updateSettings(
                        c.settings.copyWith(memoryEnabled: v),
                      ),
                    ),
                    LinearProgressIndicator(
                      value: (chars / AgentMemoryLimits.memory).clamp(0.0, 1.0),
                      minHeight: 3,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${items.length} bilgi • $chars / ${AgentMemoryLimits.memory} karakter',
                      style: TextStyle(fontSize: 11.5, color: JColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!_raw)
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ege Hafıza · Obsidian',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${c.sessions.length} sohbet · ${c.sessions.fold<int>(0, (n, s) => n + s.messages.length)} mesaj · ${c.evidenceMemory.entries.length} kaynaklı bilgi',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c.vaultStatus['connected'] == true
                            ? 'Bağlı klasör: ${c.vaultStatus['folder']}'
                            : 'Telefonda Ege Hafıza klasörü oluşturup seç. Sohbetler ve tercihler Markdown notlarına yazılır.',
                      ),
                      if (c.vaultMessage.isNotEmpty)
                        Text(
                          c.vaultMessage,
                          style: const TextStyle(fontSize: 12),
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: c.connectVault,
                            icon: const Icon(Icons.folder_open),
                            label: Text(
                              c.vaultStatus['connected'] == true
                                  ? 'Klasörü değiştir'
                                  : 'Obsidian kasasını bağla',
                            ),
                          ),
                          TextButton(
                            onPressed: c.syncVault,
                            child: const Text('Şimdi eşitle'),
                          ),
                          if (c.vaultStatus['connected'] == true)
                            TextButton(
                              onPressed: c.disconnectVault,
                              child: const Text('Bağlantıyı kes'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (c.evidenceMemory.entries.isNotEmpty)
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kaynaklı bilgiler ve çıkarımlar',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Text(
                        'Çıkarımlar kesin bilgi değildir. Yanlış olanı silebilir veya sohbette düzeltebilirsin.',
                      ),
                      for (final entry in c.evidenceMemory.entries.reversed)
                        ListTile(
                          title: Text(entry['text'].toString()),
                          subtitle: Text(
                            '${entry['kind'] == 'fact' ? 'Kullanıcı beyanı' : 'Doğrulanmamış çıkarım'} · ${(entry['sources'] as List? ?? []).length} kaynak',
                          ),
                          trailing: IconButton(
                            tooltip: 'Bu bilgiyi unut',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                c.forgetEvidence(entry['text'].toString()),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (_raw) ...[
                TextField(
                  controller: _rawCtrl,
                  minLines: 10,
                  maxLines: 24,
                  maxLength: AgentMemoryLimits.memory,
                  decoration: const InputDecoration(
                    hintText: '- Her satır bir bilgi',
                  ),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await c.setMemoryText(_rawCtrl.text);
                    if (context.mounted) {
                      showJarvisSnack(
                        context,
                        'Hafıza kaydedildi (önceki sürüm yedeklendi)',
                      );
                    }
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Kaydet'),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _add,
                        onSubmitted: (_) => _addFact(),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Yeni bilgi: "Kahvemi şekersiz içerim"',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _addFact,
                      child: const Text('Ekle'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Hafıza boş.\nSohbette "Şunu hatırla: …" ya da "hafızana kaydet: …" diyerek ekleyebilirsin; '
                      '"… bilgisini unut" ile silebilirsin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: JColors.muted, height: 1.45),
                    ),
                  ),
                for (final line in items)
                  Dismissible(
                    key: ValueKey(line),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 18),
                      color: const Color(0xFF7F1D1D),
                      child: const Icon(Icons.delete_outline_rounded),
                    ),
                    onDismissed: (_) => _removeLine(line),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.bookmark_rounded,
                        color: JColors.ok,
                        size: 18,
                      ),
                      title: Text(line.replaceFirst(RegExp(r'^[-•]\s*'), '')),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
