import 'package:flutter/material.dart';

import '../models/jarvis_models.dart';
import 'chat_palette.dart';
import '../state/jarvis_controller.dart';

Future<void> showModelPickerSheet(
  BuildContext context,
  JarvisController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFAF9F6),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => AnimatedBuilder(
      animation: controller,
      builder: (_, _) => Theme(
        data: ChatPalette.theme,
        child: _ModelPickerBody(controller: controller),
      ),
    ),
  );
}

class _ModelPickerBody extends StatefulWidget {
  final JarvisController controller;

  const _ModelPickerBody({required this.controller});

  @override
  State<_ModelPickerBody> createState() => _ModelPickerBodyState();
}

class _ModelPickerBodyState extends State<_ModelPickerBody> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesFilter(ProxyModelInfo m) {
    switch (_filter) {
      case 'gemini':
        return m.familyLabel == 'Gemini' && m.category == 'chat';
      case 'claude':
        return m.familyLabel == 'Claude' || m.familyLabel == 'Antigravity';
      case 'openai':
        return m.familyLabel == 'GPT / Codex' && m.category == 'chat';
      case 'image':
        return m.category == 'image';
      case 'tts':
        return m.category == 'tts';
      case 'other':
        return m.familyLabel == 'DersDas' ||
            m.category == 'embedding' ||
            (m.category == 'chat' &&
                m.familyLabel != 'Gemini' &&
                m.familyLabel != 'Claude' &&
                m.familyLabel != 'Antigravity' &&
                m.familyLabel != 'GPT / Codex');
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = c.proxyModels.where((m) {
      if (!_matchesFilter(m)) return false;
      if (query.isEmpty) return true;
      return m.id.toLowerCase().contains(query) ||
          m.ownedBy.toLowerCase().contains(query) ||
          m.familyLabel.toLowerCase().contains(query);
    }).toList();

    final filters = const [
      ('all', 'Tümü'),
      ('gemini', 'Gemini'),
      ('claude', 'Claude'),
      ('openai', 'GPT / Codex'),
      ('image', 'Görsel'),
      ('tts', 'Ses TTS'),
      ('other', 'Diğer'),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.94,
      minChildSize: 0.45,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFB85C3D),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Model Seç (${c.proxyModels.length})',
                        style:  TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: ChatPalette.ink,
                        ),
                      ),
                      Text(
                        '${c.settings.provider.label} • ${c.settings.baseUrl}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF74736D),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Modelleri Proxy\'den Yenile',
                  onPressed: c.testingConnection
                      ? null
                      : () => c.refreshProxyModels(silent: false),
                  icon: c.testingConnection
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFFB85C3D),
                        ),
                ),
              ],
            ),
          ),
          if (c.connectionStatusMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  c.connectionStatusMessage!,
                  style: TextStyle(
                    fontSize: 11.8,
                    color: c.connectionOk == true
                        ? const Color(0xFF34D399)
                        : const Color(0xFFFBBF24),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Model ara (claude, gpt, gemini, codex, image...)',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF0EEE8),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final f in filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      selected: _filter == f.$1,
                      label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                      onSelected: (_) => setState(() => _filter = f.$1),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 12, color: Color(0xFFE3E0D8)),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'Eşleşen model bulunamadı.',
                      style: TextStyle(color: Color(0xFF74736D)),
                    ),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: filtered.length,
                    itemBuilder: (context, idx) {
                      final m = filtered[idx];
                      // TTS satırları sohbet modeli değildir; ayrı bir seçili TTS
                      // kimliği tutulmadığından hiçbiri "seçili" gösterilmez.
                      final isSelected =
                          m.category != 'tts' && m.id == c.settings.model;
                      final icon = switch (m.category) {
                        'image' => Icons.image_outlined,
                        'tts' => Icons.record_voice_over_outlined,
                        'embedding' => Icons.scatter_plot_outlined,
                        _ => Icons.smart_toy_outlined,
                      };
                      final color = switch (m.category) {
                        'image' => const Color(0xFFF472B6),
                        'tts' => const Color(0xFF34D399),
                        'embedding' => const Color(0xFFA78BFA),
                        _ => const Color(0xFFB85C3D),
                      };
                      return ListTile(
                        dense: true,
                        leading: Icon(icon, color: color, size: 20),
                        title: Text(
                          m.id,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? const Color(0xFFB85C3D)
                                : ChatPalette.ink,
                          ),
                        ),
                        subtitle: Text(
                          '${m.familyLabel} • ${m.categoryLabel} (${m.ownedBy})',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF74736D),
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFFB85C3D),
                              )
                            : null,
                        onTap: () async {
                          final msg = await c.selectModel(m);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
