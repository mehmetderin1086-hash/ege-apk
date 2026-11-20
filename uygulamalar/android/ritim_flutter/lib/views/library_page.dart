import 'package:flutter/material.dart';
import '../ritim_models.dart';
import '../ritim_store.dart';
import '../theme_design.dart';
import 'shared_widgets.dart';

enum _LibraryTab { tracks, videos, playlists, artists, smart }

enum _TrackSort { recent, title, artist, mostPlayed }

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.controller,
    required this.onOpenPlayer,
  });

  final RitimController controller;
  final VoidCallback onOpenPlayer;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  _LibraryTab _tab = _LibraryTab.tracks;
  _TrackSort _sort = _TrackSort.recent;
  bool _onlyFavorites = false;
  String _search = '';

  RitimController get c => widget.controller;

  List<MediaTrack> get _filteredTracks {
    final q = _search.trim().toLowerCase();
    final list = c.tracks.where((t) {
      if (_onlyFavorites && !t.isFavorite) return false;
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          (t.album ?? '').toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case _TrackSort.recent:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case _TrackSort.title:
        list.sort((a, b) => a.title.compareTo(b.title));
      case _TrackSort.artist:
        list.sort((a, b) => a.artist.compareTo(b.artist));
      case _TrackSort.mostPlayed:
        list.sort((a, b) => b.playCount.compareTo(a.playCount));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final list = _filteredTracks;
    final audioCount = c.tracks.where((t) => t.kind == MediaKind.audio).length;
    final videoTracks = c.tracks.where((t) => t.kind == MediaKind.video).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              RitimHeroBanner(
                palette: p,
                assetPath: 'assets/images/ritim_library_vinyl.jpg',
                eyebrow: 'ÇEVRİMDIŞI KOLEKSİYON',
                title: 'Kitaplığım',
                subtitle:
                    '$audioCount ses parçası · ${videoTracks.length} MP4 video · ${c.playlists.length} çalma listesi',
                icon: Icons.album_rounded,
                accentColor: p.coral,
                trailing: RitimSpinningVinyl(
                  palette: p,
                  isPlaying: c.isPlaying,
                  artworkPath: c.currentTrack != null
                      ? c.artworkPathFor(c.currentTrack!)
                      : null,
                  colorIndex: c.currentTrack?.colorIndex ?? 1,
                  size: 64,
                ),
                bottom: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: c.pickAndImportLocalFiles,
                        icon: const Icon(Icons.upload_file_rounded, size: 17),
                        label: const Text('Dosya Ekle'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => showCreatePlaylistDialog(context, c),
                        icon: const Icon(Icons.playlist_add_rounded, size: 18),
                        label: const Text('Yeni Liste'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => showRitimSettingsSheet(context, c),
                      icon: const Icon(Icons.tune_rounded, size: 19),
                      tooltip: 'Ayarlar & Yedek',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _tabChip(p, _LibraryTab.tracks, 'Tümü (${c.tracks.length})'),
                    const SizedBox(width: 8),
                    _tabChip(p, _LibraryTab.videos,
                        'Videolar (${videoTracks.length})'),
                    const SizedBox(width: 8),
                    _tabChip(p, _LibraryTab.playlists,
                        'Listeler (${c.playlists.length})'),
                    const SizedBox(width: 8),
                    _tabChip(p, _LibraryTab.artists, 'Sanatçı & Albüm'),
                    const SizedBox(width: 8),
                    _tabChip(p, _LibraryTab.smart, 'Sana Özel'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_tab == _LibraryTab.videos) ...[
                if (videoTracks.isEmpty)
                  RitimGlassCard(
                    palette: p,
                    backgroundAsset: 'assets/images/ritim_search_stage.jpg',
                    backgroundOpacity: 0.22,
                    child: Column(
                      children: [
                        Icon(Icons.videocam_rounded,
                            size: 42, color: p.secondary),
                        const SizedBox(height: 8),
                        Text(
                          'Henüz indirilmiş veya eklenmiş bir MP4 video yok.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.muted),
                        ),
                      ],
                    ),
                  )
                else
                  ...videoTracks.map((t) => TrackRowTile(
                        controller: c,
                        track: t,
                        contextTracks: videoTracks,
                        onOpenPlayer: widget.onOpenPlayer,
                      )),
              ] else if (_tab == _LibraryTab.tracks) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _search = v),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Parça, sanatçı veya albüm…',
                          prefixIcon: const Icon(Icons.search_rounded, size: 19),
                          filled: true,
                          fillColor: p.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Icon(Icons.favorite_rounded, size: 16),
                      selected: _onlyFavorites,
                      onSelected: (v) => setState(() => _onlyFavorites = v),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<_TrackSort>(
                      icon: const Icon(Icons.sort_rounded),
                      onSelected: (s) => setState(() => _sort = s),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: _TrackSort.recent, child: Text('En yeni')),
                        PopupMenuItem(
                            value: _TrackSort.title, child: Text('Ada göre')),
                        PopupMenuItem(
                            value: _TrackSort.artist,
                            child: Text('Sanatçıya göre')),
                        PopupMenuItem(
                            value: _TrackSort.mostPlayed,
                            child: Text('En çok çalınan')),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (list.isEmpty)
                  RitimGlassCard(
                    palette: p,
                    child: Column(
                      children: [
                        Icon(Icons.music_off_rounded,
                            size: 40, color: p.muted),
                        const SizedBox(height: 8),
                        Text(
                          'Kütüphanede eşleşen parça yok.',
                          style: TextStyle(color: p.muted),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: c.pickAndImportLocalFiles,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Cihazdan Ekle'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            c.playTrack(list.first, context: list),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text('Tümünü Çal (${list.length})'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          final shuffled = List<MediaTrack>.from(list)
                            ..shuffle();
                          c.shuffleEnabled = true;
                          c.playTrack(shuffled.first, context: shuffled);
                        },
                        icon: const Icon(Icons.shuffle_rounded, size: 18),
                        label: const Text('Karıştır'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...list.map((t) => TrackRowTile(
                        controller: c,
                        track: t,
                        contextTracks: list,
                        onOpenPlayer: widget.onOpenPlayer,
                      )),
                ],
              ] else if (_tab == _LibraryTab.playlists) ...[
                FilledButton.icon(
                  onPressed: () => showCreatePlaylistDialog(context, c),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Yeni Çalma Listesi Oluştur'),
                ),
                const SizedBox(height: 12),
                ...c.playlists.map((pl) {
                  final plTracks = pl.trackIDs
                      .map((id) => c.tracks.where((t) => t.id == id).firstOrNull)
                      .whereType<MediaTrack>()
                      .toList();
                  final coverTrack = plTracks.firstOrNull;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RitimGlassCard(
                      palette: p,
                      radius: 18,
                      onTap: () => _openPlaylistDetail(pl, plTracks),
                      child: Row(
                        children: [
                          RitimCoverArt(
                            palette: p,
                            colorIndex: pl.id.hashCode.abs() % 6,
                            artworkPath: coverTrack != null
                                ? c.artworkPathFor(coverTrack)
                                : null,
                            size: 58,
                            radius: 14,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pl.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                const SizedBox(height: 2),
                                Text(
                                  '${plTracks.length} parça${pl.detail != null ? ' · ${pl.detail}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(color: p.muted, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          if (plTracks.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.play_circle_fill_rounded,
                                  color: p.primary, size: 32),
                              onPressed: () => c.playTrack(plTracks.first,
                                  context: plTracks),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ] else if (_tab == _LibraryTab.artists) ...[
                const Text('Sanatçılar',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ...c.artistGroups.map((ag) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RitimGlassCard(
                        palette: p,
                        radius: 16,
                        onTap: () => _openTrackGroupSheet(
                            ag.name, '${ag.tracks.length} parça', ag.tracks),
                        child: Row(
                          children: [
                            RitimCoverArt(
                              palette: p,
                              colorIndex: ag.name.hashCode.abs() % 6,
                              artworkPath: ag.artworkPath,
                              size: 48,
                              radius: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ag.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                  Text('${ag.tracks.length} parça',
                                      style: TextStyle(
                                          color: p.muted, fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    )),
                if (c.albumGroups.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Albümler',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ...c.albumGroups.map((al) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: RitimGlassCard(
                          palette: p,
                          radius: 16,
                          onTap: () => _openTrackGroupSheet(
                              al.title, al.artist, al.tracks),
                          child: Row(
                            children: [
                              RitimCoverArt(
                                palette: p,
                                colorIndex: al.title.hashCode.abs() % 6,
                                artworkPath: al.artworkPath,
                                size: 48,
                                radius: 12,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(al.title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                    Text('${al.artist} · ${al.tracks.length} parça',
                                        style: TextStyle(
                                            color: p.muted, fontSize: 12)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      )),
                ],
              ] else ...[
                ...SmartCollection.values.map((sc) {
                  final items = sc.tracksIn(c.tracks);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RitimGlassCard(
                      palette: p,
                      radius: 18,
                      onTap: () => _openTrackGroupSheet(
                        sc.title,
                        sc.detail,
                        items,
                        allowSaveAsPlaylist: true,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: p.primary.withValues(alpha: 0.14),
                            child: Icon(sc.icon, color: p.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(sc.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15.5)),
                                Text(sc.detail,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${items.length}',
                            style: TextStyle(
                                color: p.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _tabChip(RitimPalette p, _LibraryTab tab, String label) {
    final sel = _tab == tab;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      selectedColor: p.primary,
      labelStyle: TextStyle(
        color: sel ? p.background : Colors.white,
        fontWeight: FontWeight.w700,
      ),
      onSelected: (_) => setState(() => _tab = tab),
    );
  }

  void _openPlaylistDetail(MediaPlaylist pl, List<MediaTrack> items) {
    final p = c.palette;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: c,
        builder: (_, _) {
          final currentPl = c.playlists.firstWhere(
            (e) => e.id == pl.id,
            orElse: () => pl,
          );
          final liveItems = currentPl.trackIDs
              .map((id) => c.tracks.where((t) => t.id == id).firstOrNull)
              .whereType<MediaTrack>()
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.78,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(currentPl.name,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                              Text('${liveItems.length} parça',
                                  style:
                                      TextStyle(color: p.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_rounded),
                          onPressed: () {
                            final ctrl =
                                TextEditingController(text: currentPl.name);
                            showDialog<void>(
                              context: ctx,
                              builder: (dctx) => AlertDialog(
                                title: const Text('Listeyi yeniden adlandır'),
                                content: TextField(controller: ctrl),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(dctx),
                                      child: const Text('İptal')),
                                  FilledButton(
                                    onPressed: () {
                                      c.renamePlaylist(currentPl.id, ctrl.text);
                                      Navigator.pop(dctx);
                                    },
                                    child: const Text('Kaydet'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded,
                              color: p.coral),
                          onPressed: () {
                            c.deletePlaylist(currentPl.id);
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (liveItems.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () {
                          c.playTrack(liveItems.first, context: liveItems);
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Listeyi Çal'),
                      ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: liveItems.isEmpty
                          ? Center(
                              child: Text('Bu listede henüz parça yok.',
                                  style: TextStyle(color: p.muted)),
                            )
                          : ListView.builder(
                              itemCount: liveItems.length,
                              itemBuilder: (_, idx) {
                                final t = liveItems[idx];
                                return Dismissible(
                                  key: ValueKey('${currentPl.id}_${t.id}'),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 16),
                                    color: p.coral.withValues(alpha: 0.25),
                                    child: Icon(Icons.remove_circle_outline,
                                        color: p.coral),
                                  ),
                                  onDismissed: (_) => c.removeTrackFromPlaylist(
                                      currentPl.id, t.id),
                                  child: TrackRowTile(
                                    controller: c,
                                    track: t,
                                    contextTracks: liveItems,
                                    onOpenPlayer: widget.onOpenPlayer,
                                  ),
                                );
                              },
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

  void _openTrackGroupSheet(
    String title,
    String subtitle,
    List<MediaTrack> items, {
    bool allowSaveAsPlaylist = false,
  }) {
    final p = c.palette;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          Text(subtitle,
                              style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    if (allowSaveAsPlaylist && items.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          c.createPlaylist(
                            title,
                            trackIds: items.map((e) => e.id).toList(),
                            detail: subtitle,
                          );
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.playlist_add_rounded, size: 18),
                        label: const Text('Kaydet'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () {
                      c.playTrack(items.first, context: items);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text('Tümünü Çal (${items.length})'),
                  ),
                const SizedBox(height: 10),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text('Parça bulunmuyor.',
                              style: TextStyle(color: p.muted)))
                      : ListView(
                          children: items
                              .map((t) => TrackRowTile(
                                    controller: c,
                                    track: t,
                                    contextTracks: items,
                                    onOpenPlayer: widget.onOpenPlayer,
                                  ))
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
