import 'package:flutter/material.dart' hide RepeatMode;
import 'package:video_player/video_player.dart';
import '../ritim_models.dart';
import '../ritim_store.dart';
import '../theme_design.dart';

class PlayerSheet extends StatefulWidget {
  const PlayerSheet({super.key, required this.controller});

  final RitimController controller;

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet> {
  int _mode = 0; // 0: Çalar, 1: Sözler, 2: Sıra, 3: AI Notu
  bool _vinylStyle = true;
  bool _followLyrics = true;
  bool _plainLyrics = false;
  bool _showTimingOffset = false;

  RitimController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final p = c.palette;
        final track = c.currentTrack;
        if (track == null) {
          return SafeArea(
            child: Center(
              child: Text('Çalan parça yok.', style: TextStyle(color: p.muted)),
            ),
          );
        }

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: RitimAmbientBackground(
            palette: p,
            isPlaying: c.isPlaying,
            wallpaper: c.wallpaper,
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 28),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(3.5),
                            decoration: BoxDecoration(
                              color: p.surface.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                for (final item in const [
                                  (0, 'Çalar'),
                                  (1, 'Sözler'),
                                  (2, 'Sıra'),
                                  (3, 'Not'),
                                ])
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() => _mode = item.$1),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 7),
                                        decoration: BoxDecoration(
                                          color: _mode == item.$1
                                              ? p.primary
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          item.$2,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: _mode == item.$1
                                                ? p.background
                                                : Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Cihaza Kaydet',
                          onPressed: () async {
                            final ok = await c.saveTrackToDevice(track);
                            if (context.mounted && ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('“${track.title}” cihaza kaydedildi.'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.save_alt_rounded, size: 20),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Paylaş',
                          onPressed: () async {
                            final ok = await c.shareTrack(track);
                            if (!ok &&
                                context.mounted &&
                                c.statusBanner != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(c.statusBanner!)),
                              );
                            }
                          },
                          icon: const Icon(Icons.share_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: switch (_mode) {
                      0 => _buildNowPlayingTab(p, track),
                      1 => _buildLyricsTab(p, track),
                      2 => _buildQueueTab(p),
                      _ => _buildAiNoteTab(p, track),
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNowPlayingTab(RitimPalette p, MediaTrack track) {
    final dur = c.duration > 0 ? c.duration : 1.0;
    final pos = c.elapsed.clamp(0.0, dur);
    final hasVideo = track.kind == MediaKind.video &&
        c.videoController != null &&
        c.videoController!.value.isInitialized;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: hasVideo
                  ? Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border:
                            Border.all(color: p.secondary.withValues(alpha: 0.45)),
                        boxShadow: [
                          BoxShadow(
                            color: p.secondary.withValues(alpha: 0.28),
                            blurRadius: 32,
                          ),
                        ],
                      ),
                      child: AspectRatio(
                        aspectRatio: c.videoController!.value.aspectRatio > 0
                            ? c.videoController!.value.aspectRatio
                            : 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(21),
                          child: VideoPlayer(c.videoController!),
                        ),
                      ),
                    )
                  : GestureDetector(
                      onTap: () => setState(() => _vinylStyle = !_vinylStyle),
                      child: _vinylStyle
                          ? RitimSpinningVinyl(
                              palette: p,
                              isPlaying: c.isPlaying,
                              artworkPath: c.artworkPathFor(track),
                              colorIndex: track.colorIndex,
                              size: 248,
                            )
                          : Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: p.primary.withValues(alpha: 0.26),
                                    blurRadius: 36,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: RitimCoverArt(
                                palette: p,
                                colorIndex: track.colorIndex,
                                artworkPath: c.artworkPathFor(track),
                                size: 244,
                                radius: 26,
                                isPlaying: c.isPlaying,
                              ),
                            ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${track.artist}${track.album != null ? ' · ${track.album}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => c.toggleFavorite(track.id),
                icon: Icon(
                  track.isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: track.isFavorite ? p.coral : Colors.white70,
                  size: 26,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: pos,
            min: 0,
            max: dur,
            activeColor: p.primary,
            inactiveColor: p.elevated,
            onChanged: (v) => c.seekTo(v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatClock(pos),
                  style: TextStyle(color: p.muted, fontSize: 12)),
              Text(formatClock(dur),
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: c.toggleShuffle,
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: c.shuffleEnabled ? p.primary : p.muted,
                ),
              ),
              IconButton(
                onPressed: c.previousTrack,
                icon: const Icon(Icons.skip_previous_rounded, size: 36),
              ),
              FilledButton(
                onPressed: c.togglePlayPause,
                style: FilledButton.styleFrom(
                  backgroundColor: p.primary,
                  foregroundColor: p.background,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(18),
                ),
                child: Icon(
                  c.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 36,
                ),
              ),
              IconButton(
                onPressed: c.nextTrack,
                icon: const Icon(Icons.skip_next_rounded, size: 36),
              ),
              IconButton(
                onPressed: c.cycleRepeatMode,
                icon: Icon(
                  c.repeatMode == RepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  color: c.repeatMode == RepeatMode.off ? p.muted : p.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              PopupMenuButton<double>(
                onSelected: c.setPlaybackRate,
                itemBuilder: (_) => const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                    .map((r) => PopupMenuItem(value: r, child: Text('${r}x')))
                    .toList(),
                child: Chip(
                  avatar: Icon(Icons.speed_rounded, size: 16, color: p.primary),
                  label: Text('${c.playbackRate}x'),
                ),
              ),
              PopupMenuButton<int>(
                onSelected: c.setSleepTimer,
                itemBuilder: (_) => const [
                  (0, 'Kapalı'),
                  (-1, 'Parça sonu'),
                  (15, '15 dakika'),
                  (30, '30 dakika'),
                  (45, '45 dakika'),
                  (60, '60 dakika'),
                ]
                    .map((e) => PopupMenuItem(value: e.$1, child: Text(e.$2)))
                    .toList(),
                child: Chip(
                  avatar: Icon(Icons.bedtime_rounded,
                      size: 16,
                      color: c.sleepMinutes != 0 ? p.primary : p.muted),
                  label: Text(
                    c.sleepMinutes == 0
                        ? 'Uyku'
                        : (c.sleepMinutes == -1
                            ? 'Parça sonu'
                            : '${c.sleepMinutes} dk'),
                  ),
                ),
              ),
              ActionChip(
                avatar: Icon(Icons.no_encryption_gmailerrorred_rounded,
                    size: 16, color: p.muted),
                label: Text(
                  c.excludedAiTrackIds.contains(track.id)
                      ? 'AI hariç'
                      : 'AI açık',
                ),
                onPressed: () {
                  if (c.excludedAiTrackIds.contains(track.id)) {
                    c.excludedAiTrackIds.remove(track.id);
                  } else {
                    c.excludeTrackFromAi(track.id);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('AI öneri tercihi güncellendi.')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsTab(RitimPalette p, MediaTrack track) {
    final doc = c.lyrics.lyricsFor(track.id);
    final activeLine = doc?.activeLine(c.elapsed);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: c.isFetchingLyrics
                    ? null
                    : () => c.fetchLyricsFor(track),
                icon: c.isFetchingLyrics
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_rounded, size: 17),
                label: const Text('LRCLIB Getir'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => c.importLyricsFileFor(track),
                icon: const Icon(Icons.file_open_rounded, size: 17),
                label: const Text('LRC/TXT'),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _openLyricsEditor(track, doc?.rawText ?? ''),
                icon: const Icon(Icons.edit_note_rounded),
                tooltip: 'Düzenle',
              ),
            ],
          ),
        ),
        if (c.lyricsError != null)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(c.lyricsError!, style: TextStyle(color: p.coral)),
          ),
        Expanded(
          child: doc == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Bu parça için kayıtlı şarkı sözü yok. LRCLIB üzerinden arayabilir, LRC/TXT dosyası açabilir veya elle yazabilirsin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted),
                    ),
                  ),
                )
              : (_plainLyrics || doc.lines.isEmpty
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: SelectableText(
                        doc.plainText,
                        style: const TextStyle(fontSize: 16, height: 1.65),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      itemCount: doc.lines.length,
                      itemBuilder: (_, idx) {
                        final line = doc.lines[idx];
                        final active = activeLine?.id == line.id;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => c.seekTo(line.time + doc.offset),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: active
                                  ? p.primary.withValues(alpha: 0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              line.text.isEmpty ? '♪ ♪ ♪' : line.text,
                              style: TextStyle(
                                color: active ? p.primary : Colors.white70,
                                fontSize: active ? 18 : 15,
                                fontWeight:
                                    active ? FontWeight.w800 : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    )),
        ),
        if (doc != null && doc.lines.isNotEmpty)
          Container(
            color: p.surface,
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _followLyrics = !_followLyrics),
                      icon: Icon(_followLyrics
                          ? Icons.sync_rounded
                          : Icons.pan_tool_rounded),
                      label: Text(_followLyrics ? 'Takip açık' : 'Takip kapalı'),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _plainLyrics = !_plainLyrics),
                      child: Text(_plainLyrics ? 'Zamanlı' : 'Düz metin'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(
                          () => _showTimingOffset = !_showTimingOffset),
                      child: Text(
                          'Zamanlama (${doc.offset.toStringAsFixed(1)}s)'),
                    ),
                  ],
                ),
                if (_showTimingOffset)
                  Row(
                    children: [
                      IconButton(
                        onPressed: () =>
                            c.setLyricsOffset(track, doc.offset - 0.5),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Expanded(
                        child: Slider(
                          value: doc.offset,
                          min: -30,
                          max: 30,
                          divisions: 120,
                          onChanged: (v) => c.setLyricsOffset(track, v),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            c.setLyricsOffset(track, doc.offset + 0.5),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildQueueTab(RitimPalette p) {
    if (c.queue.isEmpty) {
      return Center(
          child: Text('Çalma sırası boş.', style: TextStyle(color: p.muted)));
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: c.queue.length,
      onReorderItem: (oldIndex, newIndex) =>
          c.moveQueue(oldIndex, newIndex, alreadyAdjusted: true),
      itemBuilder: (_, idx) {
        final item = c.queue[idx];
        final isCur = c.currentTrack?.id == item.id;
        return ListTile(
          key: ValueKey(item.id),
          tileColor:
              isCur ? p.primary.withValues(alpha: 0.12) : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: RitimCoverArt(
            palette: p,
            colorIndex: item.colorIndex,
            artworkPath: c.artworkPathFor(item),
            size: 42,
            radius: 10,
            isPlaying: isCur && c.isPlaying,
          ),
          title: Text(item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: isCur ? p.primary : Colors.white,
                  fontWeight: FontWeight.bold)),
          subtitle: Text(item.artist,
              maxLines: 1, style: TextStyle(color: p.muted, fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => c.removeFromQueue(idx),
              ),
              const Icon(Icons.drag_handle_rounded),
            ],
          ),
          onTap: () => c.playTrack(item),
        );
      },
    );
  }

  Widget _buildAiNoteTab(RitimPalette p, MediaTrack track) {
    final insight = c.aiInsights[track.id];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: p.secondary),
              const SizedBox(width: 8),
              const Text('AI Parça Notu',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              FilledButton.tonal(
                onPressed: c.isInsightLoading
                    ? null
                    : () => c.fetchInsightFor(track),
                child: c.isInsightLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(insight == null ? 'Not Oluştur' : 'Yenile'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (insight == null)
            Text(
              'Seçtiğin CLIProxyAPI modeli bu parça hakkında kısa bir dinleme notu ve kitaplığından benzer parçalar önerebilir.',
              style: TextStyle(color: p.muted),
            )
          else ...[
            RitimGlassCard(
              palette: p,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(insight.text,
                      style: const TextStyle(fontSize: 14.5, height: 1.5)),
                  const SizedBox(height: 8),
                  Text('Model: ${insight.model}',
                      style: TextStyle(color: p.muted, fontSize: 11)),
                ],
              ),
            ),
            if (insight.similarIDs.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Kitaplıktan benzer parçalar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...insight.similarIDs
                  .map((id) => c.tracks.where((t) => t.id == id).firstOrNull)
                  .whereType<MediaTrack>()
                  .map((sim) => ListTile(
                        title: Text(sim.title),
                        subtitle: Text(sim.artist),
                        trailing: IconButton(
                          icon: Icon(Icons.play_arrow_rounded, color: p.primary),
                          onPressed: () => c.enqueueNext(sim),
                        ),
                      )),
            ],
          ],
        ],
      ),
    );
  }

  void _openLyricsEditor(MediaTrack track, String initialText) {
    final editCtrl = TextEditingController(text: initialText);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${track.title} — Sözler'),
        content: TextField(
          controller: editCtrl,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: '[00:12.50] Satır örneği veya düz metin…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () async {
              try {
                await c.saveLyricsEdit(track, editCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}
