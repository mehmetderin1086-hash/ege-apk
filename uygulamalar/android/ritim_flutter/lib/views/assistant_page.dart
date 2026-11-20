import 'package:flutter/material.dart';
import '../ritim_ai_service.dart';
import '../ritim_models.dart';
import '../ritim_store.dart';
import '../theme_design.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    required this.controller,
    required this.onSearchYouTubeQuery,
  });

  final RitimController controller;
  final ValueChanged<String> onSearchYouTubeQuery;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _promptCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _customDjCtrl = TextEditingController();

  RitimController get c => widget.controller;

  static const _starters = [
    'Bugünkü ruh hâlime göre kütüphanemden akıcı bir liste kur.',
    'Gece dinlemek için sakin ve atmosferik şarkılar seç.',
    'Henüz hiç çalmadığım parçalardan güzel bir giriş seti öner.',
    'Türkçe akustik ve indie rock için YouTube aramaları öner.',
  ];

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = c.aiConfig.baseUrl;
    _keyCtrl.text = c.aiConfig.apiKey;
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _customDjCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final dayPart = AIDayPart.forNow();
    final selectedModel = c.aiModels
        .where((m) => m.id == c.aiConfig.selectedModelId)
        .firstOrNull;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              RitimHeroBanner(
                palette: p,
                assetPath: 'assets/images/ritim_ai_dj_deck.jpg',
                eyebrow: 'YAPAY ZEKÂ MÜZİK STÜDYOSU',
                title: 'Ritim Asistan',
                subtitle:
                    'CLIProxyAPI tüm modelleriyle canlı AI DJ seti, kişisel çalma listesi ve YouTube keşfi.',
                icon: Icons.auto_awesome_rounded,
                accentColor: p.secondary,
                trailing: Column(
                  children: [
                    IconButton.filledTonal(
                      onPressed: _openConnectionSheet,
                      icon: Icon(Icons.hub_rounded, color: p.primary, size: 20),
                      tooltip: 'CLIProxyAPI Bağlantısı',
                    ),
                    if (c.aiMessages.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      IconButton.filledTonal(
                        onPressed: c.clearAiChat,
                        icon: const Icon(Icons.delete_sweep_rounded, size: 19),
                        tooltip: 'Sohbeti temizle',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Aktif CLIProxyAPI & Model seçici çubuk
              RitimGlassCard(
                palette: p,
                radius: 18,
                onTap: c.aiModels.isEmpty
                    ? () => _openConnectionSheet()
                    : () => _openModelPickerSheet(),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: p.secondary.withValues(alpha: 0.16),
                      child:
                          Icon(Icons.auto_awesome, color: p.secondary, size: 19),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedModel != null
                                ? '${selectedModel.name} (${selectedModel.provider})'
                                : (c.aiConfig.selectedModelId.isNotEmpty
                                    ? c.aiConfig.selectedModelId
                                    : 'Model seç veya CLIProxy bağla'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          Text(
                            '${c.aiConfig.mode.title} · ${c.aiModels.length} model yüklü',
                            style: TextStyle(color: p.muted, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed:
                          c.isLoadingModels ? null : () => c.loadAiModels(),
                      child: c.isLoadingModels
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(c.aiModels.isEmpty ? 'Modelleri Çek' : 'Seç'),
                    ),
                  ],
                ),
              ),
              if (c.aiError != null) ...[
                const SizedBox(height: 10),
                RitimGlassCard(
                  palette: p,
                  radius: 14,
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: p.coral, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(c.aiError!,
                            style: TextStyle(color: p.coral, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // AI DJ Stüdyosu
              RitimGlassCard(
                palette: p,
                radius: 20,
                glowColor: c.djSession != null ? p.primary : p.secondary,
                backgroundAsset: 'assets/images/ritim_studio_backdrop.jpg',
                backgroundOpacity: 0.24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.album_rounded, color: p.primary, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('AI DJ',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              Text('Ruh hâlini seç, set kendini sürdürsün',
                                  style: TextStyle(
                                      fontSize: 11.5, color: Colors.white60)),
                            ],
                          ),
                        ),
                        if (c.djSession != null)
                          TextButton(
                            onPressed: c.stopAiDj,
                            child: Text('Bitir',
                                style: TextStyle(color: p.coral)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: dayPart.presets.map((preset) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar:
                                  Icon(preset.icon, size: 16, color: p.primary),
                              label: Text(preset.title),
                              backgroundColor: p.elevated,
                              onPressed: c.isDjLoading
                                  ? null
                                  : () => c.startAiDj(preset.prompt),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (c.djSession != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: p.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'DJ Yayında: ${c.djSession!.note}',
                          style: TextStyle(color: p.primary, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Başlangıç önerileri (sohbet boşsa)
              if (c.aiMessages.isEmpty) ...[
                ..._starters.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RitimGlassCard(
                        palette: p,
                        radius: 14,
                        padding: const EdgeInsets.all(13),
                        onTap: () {
                          _promptCtrl.text = s;
                        },
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(s,
                                    style: const TextStyle(fontSize: 13.5))),
                            Icon(Icons.north_west_rounded,
                                size: 16, color: p.primary),
                          ],
                        ),
                      ),
                    )),
                const SizedBox(height: 8),
                Text(
                  'Kütüphanende ${c.tracks.length} parça var. Ses dosyaları değil, yalnızca parça adı/sanatçı/dinleme metadatası seçtiğin CLIProxyAPI modeline iletilir.',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
              ],
              // Mesajlar
              ...c.aiMessages.map((msg) => _buildMessageCard(p, msg)),
              const SizedBox(height: 12),
              // Mesaj gönderme kutusu
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) {
                        c.sendAiChat(v);
                        _promptCtrl.clear();
                      },
                      decoration: InputDecoration(
                        hintText: 'Ritim Asistan’a sor veya liste iste…',
                        filled: true,
                        fillColor: p.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: c.isSendingAi
                        ? null
                        : () {
                            final t = _promptCtrl.text;
                            _promptCtrl.clear();
                            c.sendAiChat(t);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      foregroundColor: p.background,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(14),
                    ),
                    child: c.isSendingAi
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: p.background),
                          )
                        : const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageCard(RitimPalette p, AIMessage msg) {
    final isUser = msg.role == 'user';
    final playlistTracks = msg.playlist?.trackIDs
            .map((id) => c.tracks.where((t) => t.id == id).firstOrNull)
            .whereType<MediaTrack>()
            .toList() ??
        const <MediaTrack>[];

    return Padding(
      padding: EdgeInsets.only(
        bottom: 12,
        left: isUser ? 32 : 0,
        right: isUser ? 0 : 20,
      ),
      child: RitimGlassCard(
        palette: p,
        radius: 18,
        glowColor: isUser ? null : p.secondary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUser ? Icons.person_rounded : Icons.auto_awesome_rounded,
                  size: 15,
                  color: isUser ? p.muted : p.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  isUser ? 'Sen' : 'Ritim Asistan',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isUser ? p.muted : p.secondary,
                  ),
                ),
                const Spacer(),
                if (!isUser && msg.model != null)
                  Text(msg.model!,
                      style: TextStyle(color: p.muted, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(msg.content,
                style: const TextStyle(fontSize: 14, height: 1.4)),
            if (!isUser && msg.appliedNote != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  msg.appliedNote!,
                  style: TextStyle(
                      color: p.primary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
            if (!isUser && playlistTracks.isNotEmpty && msg.playlist != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.background.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(msg.playlist!.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14.5)),
                    Text('${playlistTracks.length} parça',
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () => c.playTrack(playlistTracks.first,
                              context: playlistTracks),
                          icon: const Icon(Icons.play_arrow_rounded, size: 17),
                          label: const Text('Çal'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            c.createPlaylist(
                              msg.playlist!.name,
                              trackIds: playlistTracks.map((e) => e.id).toList(),
                              detail: 'Ritim Asistan önerisi',
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      '“${msg.playlist!.name}” kaydedildi.')),
                            );
                          },
                          icon: const Icon(Icons.playlist_add_rounded, size: 17),
                          label: const Text('Listeye Kaydet'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (!isUser && msg.searchQueries.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('YouTube’da keşfet',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...msg.searchQueries.map((q) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () => widget.onSearchYouTubeQuery(q),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 9),
                        decoration: BoxDecoration(
                          color: p.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded,
                                size: 16, color: p.primary),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(q,
                                    style: TextStyle(
                                        color: p.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5))),
                            Icon(Icons.arrow_forward_rounded,
                                size: 16, color: p.primary),
                          ],
                        ),
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  void _openConnectionSheet() {
    final p = c.palette;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: c,
        builder: (_, _) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                18, 4, 18, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CLIProxyAPI / Yapay Zekâ Bağlantısı',
                      style:
                          TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: RitimAiBackendMode.values.map((m) {
                      return ChoiceChip(
                        label: Text(m.title),
                        selected: c.aiConfig.mode == m,
                        onSelected: (_) {
                          if (m.defaultUrl.isNotEmpty) {
                            _urlCtrl.text = m.defaultUrl;
                          }
                          c.updateAiConnection(mode: m, baseUrl: _urlCtrl.text);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  if (c.aiConfig.mode != RitimAiBackendMode.directGemini)
                    TextField(
                      controller: _urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'CLIProxyAPI Sunucu Adresi',
                        hintText: 'http://127.0.0.1:8317',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Erişim Anahtarı (Bearer / API Key)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('Yetki Başlığı:', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Bearer'),
                        selected: c.aiConfig.authHeader == 'Authorization',
                        onSelected: (_) => c.updateAiConnection(
                            authHeader: 'Authorization'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('X-Personal-Token'),
                        selected: c.aiConfig.authHeader == 'X-Personal-Token',
                        onSelected: (_) => c.updateAiConnection(
                            authHeader: 'X-Personal-Token'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await c.updateAiConnection(
                          baseUrl: _urlCtrl.text,
                          apiKey: _keyCtrl.text,
                        );
                        await c.loadAiModels();
                        if (ctx.mounted && c.aiModels.isNotEmpty) {
                          Navigator.pop(ctx);
                          _openModelPickerSheet();
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: p.primary,
                        foregroundColor: p.background,
                      ),
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Kaydet & Tüm Modelleri Getir'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openModelPickerSheet() {
    final p = c.palette;
    var query = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final filtered = c.aiModels.where((m) {
            final q = query.trim().toLowerCase();
            if (q.isEmpty) return true;
            return m.id.toLowerCase().contains(q) ||
                m.name.toLowerCase().contains(q) ||
                m.provider.toLowerCase().contains(q);
          }).toList();

          final grouped = <String, List<RitimAIModel>>{};
          for (final m in filtered) {
            grouped.putIfAbsent(m.provider, () => []).add(m);
          }

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.78,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tüm Modeller (${c.aiModels.length})',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(
                      onChanged: (v) => setModalState(() => query = v),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Model ara (gemini, claude, gpt, qwen, deepseek)…',
                        prefixIcon: Icon(Icons.search_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView(
                        children: grouped.entries.expand((entry) {
                          return [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                              child: Text(
                                '${entry.key} (${entry.value.length})',
                                style: TextStyle(
                                  color: p.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            ...entry.value.map((m) {
                              final sel = m.id == c.aiConfig.selectedModelId;
                              return ListTile(
                                dense: true,
                                selected: sel,
                                selectedTileColor:
                                    p.primary.withValues(alpha: 0.12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                title: Text(m.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(m.id,
                                    style: TextStyle(
                                        color: p.muted, fontSize: 11)),
                                trailing: sel
                                    ? Icon(Icons.check_circle_rounded,
                                        color: p.primary)
                                    : null,
                                onTap: () {
                                  c.updateAiConnection(selectedModelId: m.id);
                                  Navigator.pop(ctx);
                                },
                              );
                            }),
                          ];
                        }).toList(),
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
}
