import 'package:flutter/material.dart';
import '../ritim_models.dart';
import '../ritim_store.dart';
import '../theme_design.dart';

class TrackRowTile extends StatelessWidget {
  const TrackRowTile({
    super.key,
    required this.controller,
    required this.track,
    required this.contextTracks,
    this.onOpenPlayer,
  });

  final RitimController controller;
  final MediaTrack track;
  final List<MediaTrack> contextTracks;
  final VoidCallback? onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final p = controller.palette;
    final isCurrent = controller.currentTrack?.id == track.id;
    final playingHere = isCurrent && controller.isPlaying;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RitimGlassCard(
        palette: p,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: 16,
        glowColor: isCurrent ? p.primary : null,
        onTap: () {
          controller.playTrack(track, context: contextTracks);
          if (track.kind == MediaKind.video && onOpenPlayer != null) {
            onOpenPlayer!();
          }
        },
        child: Row(
          children: [
            RitimCoverArt(
              palette: p,
              colorIndex: track.colorIndex,
              artworkPath: controller.artworkPathFor(track),
              isVideo: track.kind == MediaKind.video,
              size: 50,
              radius: 12,
              isPlaying: playingHere,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? p.primary : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      if (track.kind == MediaKind.video) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: p.secondary.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'VİDEO',
                            style: TextStyle(
                              color: p.secondary,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${track.artist}${track.duration > 0 ? ' · ${formatClock(track.duration)}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => controller.toggleFavorite(track.id),
              icon: Icon(
                track.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: track.isFavorite ? p.coral : p.muted,
                size: 20,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  showTrackOptionsSheet(context, controller, track, contextTracks),
              icon: Icon(Icons.more_horiz_rounded, color: p.muted, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

void showTrackOptionsSheet(
  BuildContext context,
  RitimController controller,
  MediaTrack track,
  List<MediaTrack> contextTracks,
) {
  final p = controller.palette;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: RitimCoverArt(
                  palette: p,
                  colorIndex: track.colorIndex,
                  artworkPath: controller.artworkPathFor(track),
                  isVideo: track.kind == MediaKind.video,
                  size: 46,
                  radius: 10,
                ),
                title: Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${track.artist} · ${formatBytes(track.fileSize)}',
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ),
              const Divider(),
              _optTile(ctx, Icons.play_arrow_rounded, 'Şimdi çal', p.primary, () {
                controller.playTrack(track, context: contextTracks);
              }),
              _optTile(
                  ctx, Icons.playlist_play_rounded, 'Sırada sonraki yap', p.secondary, () {
                controller.enqueueNext(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('“${track.title}” sonraki sıraya alındı.')),
                );
              }),
              _optTile(ctx, Icons.queue_music_rounded, 'Sıranın sonuna ekle', p.muted, () {
                controller.enqueue(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('“${track.title}” sıraya eklendi.')),
                );
              }),
              _optTile(ctx, Icons.playlist_add_rounded, 'Çalma listesine ekle', p.primary, () {
                showPickPlaylistSheet(context, controller, track);
              }),
              _optTile(ctx, Icons.edit_rounded, 'Ad ve sanatçı düzenle', Colors.white, () {
                showEditTrackDialog(context, controller, track);
              }),
              _optTile(ctx, Icons.share_rounded, 'Dosyayı paylaş', p.secondary,
                  () async {
                final ok = await controller.shareTrack(track);
                if (!ok && context.mounted && controller.statusBanner != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(controller.statusBanner!)),
                  );
                }
              }),
              _optTile(ctx, Icons.save_alt_rounded,
                  'Cihaza kaydet (İndirilenler)', p.primary, () async {
                final ok = await controller.saveTrackToDevice(track);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? '“${track.title}” cihaza kaydedildi.'
                            : (controller.statusBanner ??
                                'Kaydetme iptal edildi.'),
                      ),
                    ),
                  );
                }
              }),
              _optTile(ctx, Icons.delete_outline_rounded, 'Kütüphaneden sil', p.coral, () {
                controller.deleteTrack(track.id);
              }),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _optTile(
  BuildContext ctx,
  IconData icon,
  String title,
  Color color,
  VoidCallback onTap,
) {
  return ListTile(
    leading: Icon(icon, color: color),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    onTap: () {
      Navigator.pop(ctx);
      onTap();
    },
  );
}

void showPickPlaylistSheet(
  BuildContext context,
  RitimController controller,
  MediaTrack track,
) {
  final p = controller.palette;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Listeye ekle',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: p.primary.withValues(alpha: 0.16),
                child: Icon(Icons.add_rounded, color: p.primary),
              ),
              title: const Text('Yeni liste oluştur ve ekle'),
              onTap: () {
                Navigator.pop(ctx);
                showCreatePlaylistDialog(
                  context,
                  controller,
                  initialTrackIds: [track.id],
                );
              },
            ),
            if (controller.playlists.isNotEmpty) const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: controller.playlists.map((pl) {
                  final exists = pl.trackIDs.contains(track.id);
                  return ListTile(
                    leading: Icon(
                      exists
                          ? Icons.check_circle_rounded
                          : Icons.queue_music_rounded,
                      color: exists ? p.primary : p.muted,
                    ),
                    title: Text(pl.name),
                    subtitle: Text('${pl.trackIDs.length} parça',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                    onTap: () {
                      controller.addTrackToPlaylist(pl.id, track.id);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text('“${track.title}” · ${pl.name} listesine eklendi.')),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void showCreatePlaylistDialog(
  BuildContext context,
  RitimController controller, {
  List<String> initialTrackIds = const [],
}) {
  final nameCtrl = TextEditingController();
  final detailCtrl = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Yeni çalma listesi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Liste adı',
              hintText: 'Örn. Akşam Sürüşü',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: detailCtrl,
            decoration: const InputDecoration(
              labelText: 'Açıklama (isteğe bağlı)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            controller.createPlaylist(
              name,
              trackIds: initialTrackIds,
              detail: detailCtrl.text.trim().isEmpty
                  ? null
                  : detailCtrl.text.trim(),
            );
            Navigator.pop(ctx);
          },
          child: const Text('Oluştur'),
        ),
      ],
    ),
  );
}

void showEditTrackDialog(
  BuildContext context,
  RitimController controller,
  MediaTrack track,
) {
  final titleCtrl = TextEditingController(text: track.title);
  final artistCtrl = TextEditingController(text: track.artist);
  final albumCtrl = TextEditingController(text: track.album ?? '');
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Parça bilgilerini düzenle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Parça adı',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: artistCtrl,
            decoration: const InputDecoration(
              labelText: 'Sanatçı',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: albumCtrl,
            decoration: const InputDecoration(
              labelText: 'Albüm',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: () {
            controller.updateTrackMeta(
              track.id,
              title: titleCtrl.text,
              artist: artistCtrl.text,
              album: albumCtrl.text,
            );
            Navigator.pop(ctx);
          },
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
}

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({
    super.key,
    required this.controller,
    required this.onTap,
  });

  final RitimController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final track = controller.currentTrack;
    if (track == null) return const SizedBox.shrink();
    final p = controller.palette;
    final progress = controller.duration > 0
        ? (controller.elapsed / controller.duration).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: RitimGlassCard(
        palette: p,
        radius: 20,
        padding: EdgeInsets.zero,
        glowColor: p.primary,
        backgroundAsset: 'assets/images/ritim_download_studio.jpg',
        backgroundOpacity: 0.24,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                children: [
                  if (track.kind == MediaKind.video)
                    RitimCoverArt(
                      palette: p,
                      colorIndex: track.colorIndex,
                      artworkPath: controller.artworkPathFor(track),
                      isVideo: true,
                      size: 46,
                      radius: 12,
                      isPlaying: controller.isPlaying,
                    )
                  else
                    RitimSpinningVinyl(
                      palette: p,
                      isPlaying: controller.isPlaying,
                      artworkPath: controller.artworkPathFor(track),
                      colorIndex: track.colorIndex,
                      size: 46,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (controller.isPlaying) ...[
                              PlayingBars(
                                isPlaying: true,
                                color: p.primary,
                                size: 13,
                                barCount: 3,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${track.artist} · ${formatClock(controller.elapsed)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => controller.toggleFavorite(track.id),
                    icon: Icon(
                      track.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: track.isFavorite ? p.coral : p.muted,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.togglePlayPause,
                    icon: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [p.primary, p.secondary],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: p.primary.withValues(alpha: 0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(
                        controller.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: p.background,
                        size: 21,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.nextTrack,
                    icon: const Icon(Icons.skip_next_rounded, size: 22),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(20)),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(p.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showRitimSettingsSheet(
  BuildContext context,
  RitimController controller,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ListenableBuilder(
      listenable: controller,
      builder: (_, _) {
        final p = controller.palette;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ritim Ayarları',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      'Canlı arka plan resmi, neon renk teması ve .ritimbackup yedekleme',
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  const SizedBox(height: 18),
                  const Text('Arka Plan Duvar Kâğıdı',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 98,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: RitimWallpaper.values.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, idx) {
                        final wp = RitimWallpaper.values[idx];
                        final selected = controller.wallpaper == wp;
                        return GestureDetector(
                          onTap: () => controller.setWallpaper(wp),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 138,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected
                                      ? p.primary
                                      : Colors.white.withValues(alpha: 0.14),
                                  width: selected ? 2 : 1,
                                ),
                                color: p.elevated,
                              ),
                              child: Stack(
                                children: [
                                  if (wp.assetPath != null)
                                    Positioned.fill(
                                      child: Image.asset(
                                        wp.assetPath!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.25),
                                            Colors.black.withValues(alpha: 0.82),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(wp.icon,
                                                size: 16,
                                                color: selected
                                                    ? p.primary
                                                    : Colors.white70),
                                            const Spacer(),
                                            if (selected)
                                              Icon(Icons.check_circle_rounded,
                                                  size: 16, color: p.primary),
                                          ],
                                        ),
                                        const Spacer(),
                                        Text(
                                          wp.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: selected
                                                ? p.primary
                                                : Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          wp.subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10,
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
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Tema Stili',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.55,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: RitimThemeStyle.values.map((style) {
                      final sp = RitimPalette.of(style);
                      final selected = controller.themeStyle == style;
                      return RitimGlassCard(
                        palette: p,
                        radius: 14,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        glowColor: selected ? sp.primary : null,
                        onTap: () => controller.setTheme(style),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 13,
                              backgroundColor: sp.primary,
                              child: Icon(style.icon,
                                  size: 14, color: sp.background),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(style.title,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                          color: selected
                                              ? sp.primary
                                              : Colors.white)),
                                  Text(style.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: p.muted, fontSize: 10)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  const Text('Kütüphane ve Yedek',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    tileColor: p.elevated,
                    leading: Icon(Icons.upload_file_rounded, color: p.primary),
                    title: const Text('Cihazdan ses/video içe aktar'),
                    subtitle: const Text('MP3, M4A, WAV, MP4 seç'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await controller.pickAndImportLocalFiles();
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    tileColor: p.elevated,
                    leading: Icon(Icons.find_in_page_rounded,
                        color: p.secondary),
                    title: const Text('Meta verileri yeniden tara'),
                    subtitle: const Text('Süre, sanatçı, albüm ve kapakları yenile'),
                    trailing: controller.isScanningMetadata
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: () async {
                      final count = await controller.rescanAllMetadata();
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                              content:
                                  Text('$count parça bilgisi güncellendi.')),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final ok =
                                await controller.exportBackup(includeAudio: true);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? '.ritimbackup paketi kaydedildi.'
                                      : 'Yedekleme iptal edildi.'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.archive_rounded, size: 18),
                          label: const Text('Yedeği Dışa Aktar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final msg =
                                  await controller.importBackupFromDevice();
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(msg)));
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('$e')));
                              }
                            }
                          },
                          icon: const Icon(Icons.unarchive_rounded, size: 18),
                          label: const Text('Yedek Yükle'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      'Ritim Android v1.11.0 · ${controller.tracks.length} parça · ${controller.playlists.length} liste',
                      style: TextStyle(color: p.muted, fontSize: 11.5),
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
