import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ritim_models.dart';
import '../ritim_store.dart';
import '../theme_design.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({
    super.key,
    required this.controller,
    this.onOpenPlayer,
  });

  final RitimController controller;
  final VoidCallback? onOpenPlayer;

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final _urlCtrl = TextEditingController();
  final _playlistUrlCtrl = TextEditingController();
  final Set<String> _selectedPlaylistItemIds = {};

  RitimController get c => widget.controller;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _playlistUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteAndFill(TextEditingController target) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text?.trim() ?? '';
    if (txt.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Panoda bağlantı bulunamadı.')),
        );
      }
      return;
    }
    setState(() => target.text = txt);
  }

  Future<void> _submitSingleUrl({DownloadFormat? overrideFormat}) async {
    final raw = _urlCtrl.text.trim();
    if (raw.isEmpty) return;
    try {
      final fmt = overrideFormat ?? c.defaultFormat;
      await c.enqueueDownload(
        raw,
        format: fmt,
        quality: c.defaultQuality,
      );
      _urlCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${fmt == DownloadFormat.mp4 ? "MP4 Video" : "MP3 Ses"} kuyruğa eklendi.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('RitimException: ', ''))),
        );
      }
    }
  }

  Future<void> _resolvePlaylist() async {
    final raw = _playlistUrlCtrl.text.trim();
    if (raw.isEmpty) return;
    await c.previewYouTubePlaylist(raw);
    if (c.playlistPreview != null) {
      setState(() {
        _selectedPlaylistItemIds
          ..clear()
          ..addAll(c.playlistPreview!.items.map((e) => e.id));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final activeCount = c.downloadEntries.where((e) => e.isActive).length;
    final completedCount = c.downloadEntries
        .where((e) => e.status == DownloadStatus.completed)
        .length;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              RitimHeroBanner(
                palette: p,
                assetPath: 'assets/images/ritim_download_studio.jpg',
                eyebrow: 'STÜDYO AKTARIM MOTORU',
                title: 'İndirmeler',
                subtitle:
                    'YouTube’dan MP3/M4A ses ve MP4 videoları yüksek hızda, kapak resmiyle birlikte indir.',
                icon: Icons.downloading_rounded,
                accentColor: p.primary,
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.46),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: p.primary.withValues(alpha: 0.36)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$completedCount',
                        style: TextStyle(
                          color: p.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'Tamam',
                        style: TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Resimli Biçim Seçici Kartlar (MP3 Ses vs MP4 Video)
              Row(
                children: [
                  Expanded(
                    child: _formatSelectorCard(
                      p: p,
                      title: 'MP3 / Ses',
                      subtitle: 'M4A kayıpsız ses',
                      icon: Icons.headphones_rounded,
                      assetPath: 'assets/images/ritim_library_vinyl.jpg',
                      accent: p.primary,
                      selected: c.defaultFormat == DownloadFormat.mp3,
                      onTap: () => c.setDefaultDownloadPrefs(
                          format: DownloadFormat.mp3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _formatSelectorCard(
                      p: p,
                      title: 'MP4 Video',
                      subtitle: 'HD klip & video',
                      icon: Icons.movie_creation_rounded,
                      assetPath: 'assets/images/ritim_search_stage.jpg',
                      accent: p.secondary,
                      selected: c.defaultFormat == DownloadFormat.mp4,
                      onTap: () => c.setDefaultDownloadPrefs(
                          format: DownloadFormat.mp4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Tekil URL & Biçim/Kalite kartı
              RitimGlassCard(
                palette: p,
                radius: 20,
                glowColor: c.defaultFormat == DownloadFormat.mp4
                    ? p.secondary
                    : p.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.link_rounded, color: p.primary, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'YouTube veya doğrudan medya indir',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _pasteAndFill(_urlCtrl),
                          icon: const Icon(Icons.content_paste_rounded,
                              size: 16),
                          label: const Text('Yapıştır'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlCtrl,
                      keyboardType: TextInputType.url,
                      onSubmitted: (_) => _submitSingleUrl(),
                      decoration: InputDecoration(
                        hintText: 'https://www.youtube.com/watch?v=…',
                        filled: true,
                        fillColor: p.background.withValues(alpha: 0.68),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.download_for_offline_rounded,
                              color: p.primary),
                          onPressed: _submitSingleUrl,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ChoiceChip(
                          label: Text(DownloadQuality.standard.title),
                          selected:
                              c.defaultQuality == DownloadQuality.standard,
                          onSelected: (_) => c.setDefaultDownloadPrefs(
                              quality: DownloadQuality.standard),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(DownloadQuality.highest.title),
                          selected: c.defaultQuality == DownloadQuality.highest,
                          onSelected: (_) => c.setDefaultDownloadPrefs(
                              quality: DownloadQuality.highest),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      c.defaultQuality.detail(c.defaultFormat),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Eşzamanlı: ${c.maxConcurrency}',
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                        Expanded(
                          child: Slider(
                            value: c.maxConcurrency.toDouble(),
                            min: 2,
                            max: 20,
                            divisions: 18,
                            activeColor: p.primary,
                            onChanged: (v) => c.setMaxConcurrency(v.round()),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () =>
                                _submitSingleUrl(overrideFormat: DownloadFormat.mp3),
                            style: FilledButton.styleFrom(
                              backgroundColor: p.primary,
                              foregroundColor: p.background,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.audiotrack_rounded, size: 18),
                            label: const Text('MP3 İndir',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () =>
                                _submitSingleUrl(overrideFormat: DownloadFormat.mp4),
                            style: FilledButton.styleFrom(
                              backgroundColor: p.secondary,
                              foregroundColor: p.background,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.videocam_rounded, size: 18),
                            label: const Text('MP4 İndir',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Oynatma Listesi / Mix Çözümleyici
              RitimGlassCard(
                palette: p,
                radius: 20,
                backgroundAsset: 'assets/images/ritim_night_drive_bg.jpg',
                backgroundOpacity: 0.18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.playlist_play_rounded,
                            color: p.secondary, size: 22),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'YouTube Oynatma Listesi / Mix İndir',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Panodan Yapıştır',
                          onPressed: () => _pasteAndFill(_playlistUrlCtrl),
                          icon: Icon(Icons.content_paste_rounded,
                              size: 18, color: p.secondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _playlistUrlCtrl,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'https://www.youtube.com/playlist?list=…',
                              filled: true,
                              fillColor: p.background.withValues(alpha: 0.65),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed:
                              c.isLoadingPlaylist ? null : _resolvePlaylist,
                          child: c.isLoadingPlaylist
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Çözümle'),
                        ),
                      ],
                    ),
                    if (c.statusBanner != null) ...[
                      const SizedBox(height: 8),
                      Text(c.statusBanner!,
                          style: TextStyle(color: p.coral, fontSize: 12)),
                    ],
                    if (c.playlistPreview != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${c.playlistPreview!.title} (${_selectedPlaylistItemIds.length}/${c.playlistPreview!.items.length})',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                if (_selectedPlaylistItemIds.length ==
                                    c.playlistPreview!.items.length) {
                                  _selectedPlaylistItemIds.clear();
                                } else {
                                  _selectedPlaylistItemIds.addAll(c
                                      .playlistPreview!.items
                                      .map((e) => e.id));
                                }
                              });
                            },
                            child: Text(_selectedPlaylistItemIds.length ==
                                    c.playlistPreview!.items.length
                                ? 'Hiçbiri'
                                : 'Tümü'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: c.playlistPreview!.items.length,
                          itemBuilder: (_, idx) {
                            final item = c.playlistPreview!.items[idx];
                            final checked =
                                _selectedPlaylistItemIds.contains(item.id);
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: checked,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedPlaylistItemIds.add(item.id);
                                  } else {
                                    _selectedPlaylistItemIds.remove(item.id);
                                  }
                                });
                              },
                              title: Text(item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: Text(item.artist,
                                  maxLines: 1,
                                  style:
                                      TextStyle(color: p.muted, fontSize: 11)),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _selectedPlaylistItemIds.isEmpty
                              ? null
                              : () async {
                                  final selected = c.playlistPreview!.items
                                      .where((i) => _selectedPlaylistItemIds
                                          .contains(i.id))
                                      .toList();
                                  final count =
                                      await c.enqueueSelectedPlaylistItems(
                                    selected,
                                    playlistName: c.playlistPreview!.title,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '$count parça kuyruğa eklendi ve liste oluşturuldu.'),
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.queue_rounded),
                          label: Text(
                              'Seçili ${_selectedPlaylistItemIds.length} Parçayı İndir'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    'Kuyruk (${c.downloadEntries.length})',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  if (activeCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$activeCount etkin',
                        style: TextStyle(
                            color: p.primary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  if (c.downloadEntries.any((e) =>
                      e.status == DownloadStatus.completed ||
                      e.status == DownloadStatus.cancelled))
                    TextButton.icon(
                      onPressed: c.clearFinishedDownloads,
                      icon: const Icon(Icons.cleaning_services_rounded,
                          size: 16),
                      label: const Text('Temizle'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (c.downloadEntries.isEmpty)
                RitimGlassCard(
                  palette: p,
                  child: Text(
                    'Henüz indirme görevi yok. Yukarıdan bir YouTube video/oynatma listesi bağlantısı yapıştır veya Ara sekmesinden MP3 / MP4 seç.',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                )
              else
                ...c.downloadEntries.map((entry) => _buildEntryCard(p, entry)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _formatSelectorCard({
    required RitimPalette p,
    required String title,
    required String subtitle,
    required IconData icon,
    required String assetPath,
    required Color accent,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return RitimPress(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: 0.12),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: accent.withValues(alpha: 0.24),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: p.elevated),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        p.background.withValues(alpha: selected ? 0.45 : 0.68),
                        p.background.withValues(alpha: 0.90),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: selected
                            ? accent
                            : accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: selected ? p.background : accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? accent : Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryCard(RitimPalette p, DownloadEntry e) {
    final speedLabel = e.bytesPerSecond != null && e.bytesPerSecond! > 100
        ? ' · ${formatBytes(e.bytesPerSecond!.round())}/sn'
        : '';
    final bytesLabel = e.receivedBytes != null
        ? (e.expectedBytes != null && e.expectedBytes! > 0
            ? '${formatBytes(e.receivedBytes!)} / ${formatBytes(e.expectedBytes!)}'
            : formatBytes(e.receivedBytes!))
        : '';
    final ytId = Uri.tryParse(e.sourceURL)?.queryParameters['v'];
    final isVideo = e.format == DownloadFormat.mp4;
    final accent = isVideo ? p.secondary : p.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RitimGlassCard(
        palette: p,
        radius: 18,
        padding: const EdgeInsets.all(12),
        glowColor: e.isActive ? accent : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (ytId != null && ytId.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      'https://i.ytimg.com/vi/$ytId/mqdefault.jpg',
                      width: 58,
                      height: 42,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 58,
                        height: 42,
                        color: p.elevated,
                        child: Icon(
                          isVideo
                              ? Icons.videocam_rounded
                              : Icons.audiotrack_rounded,
                          color: accent,
                          size: 20,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 44,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.videocam_rounded
                          : Icons.audiotrack_rounded,
                      color: accent,
                      size: 20,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              isVideo ? 'MP4 VİDEO' : 'MP3 SES',
                              style: TextStyle(
                                color: accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${e.stage?.title ?? e.status.title}'
                        '${e.resolvedQuality != null ? ' · ${e.resolvedQuality}' : ''}'
                        '${bytesLabel.isNotEmpty ? ' · $bytesLabel$speedLabel' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                if (e.isActive)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => c.cancelDownload(e.id),
                    icon: const Icon(Icons.close_rounded, size: 19),
                    tooltip: 'İptal',
                  )
                else if (e.status == DownloadStatus.failed ||
                    e.status == DownloadStatus.cancelled)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => c.retryDownload(e.id),
                    icon: Icon(Icons.refresh_rounded, color: p.primary, size: 21),
                    tooltip: 'Yeniden dene',
                  )
                else if (e.status == DownloadStatus.completed &&
                    e.trackID != null) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final match =
                          c.tracks.where((t) => t.id == e.trackID).firstOrNull;
                      if (match != null) {
                        final ok = await c.shareTrack(match);
                        if (!ok && mounted && c.statusBanner != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(c.statusBanner!)),
                          );
                        }
                      }
                    },
                    icon: Icon(Icons.share_rounded, color: p.muted, size: 20),
                    tooltip: 'Paylaş',
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final match =
                          c.tracks.where((t) => t.id == e.trackID).firstOrNull;
                      if (match != null) {
                        c.playTrack(match, context: c.tracks);
                        if (match.kind == MediaKind.video &&
                            widget.onOpenPlayer != null) {
                          widget.onOpenPlayer!();
                        }
                      }
                    },
                    icon: Icon(Icons.play_circle_fill_rounded,
                        color: accent, size: 28),
                    tooltip: 'Çal',
                  ),
                ],
              ],
            ),
            if (e.isActive) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: e.progress > 0.03 ? e.progress : null,
                  minHeight: 5.5,
                  color: accent,
                  backgroundColor: p.elevated,
                ),
              ),
            ],
            if (e.error != null) ...[
              const SizedBox(height: 6),
              Text(
                e.error!,
                style: TextStyle(color: p.coral, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
