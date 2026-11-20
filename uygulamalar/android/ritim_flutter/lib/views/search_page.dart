import 'package:flutter/material.dart';
import '../ritim_models.dart';
import '../ritim_store.dart';
import '../theme_design.dart';
import 'shared_widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.controller,
    this.initialQuery,
    required this.onOpenDownloads,
    this.onOpenPlayer,
  });

  final RitimController controller;
  final String? initialQuery;
  final VoidCallback onOpenDownloads;
  final VoidCallback? onOpenPlayer;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchCtrl = TextEditingController();
  bool _youtubeMode = true;
  DownloadQuality _quality = DownloadQuality.standard;

  RitimController get c => widget.controller;

  static const _quickTags = [
    'Piyano ile Türküler',
    'Türkçe Akustik',
    'Gece Lo-Fi Beats',
    'Anadolu Rock',
    'Enstrümantal Piyano',
    'Sakin Çalışma Müzikleri',
  ];

  @override
  void initState() {
    super.initState();
    _quality = c.defaultQuality;
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchCtrl.text = widget.initialQuery!;
    }
  }

  @override
  void didUpdateWidget(SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != null &&
        widget.initialQuery != oldWidget.initialQuery &&
        widget.initialQuery!.isNotEmpty) {
      _searchCtrl.text = widget.initialQuery!;
      _youtubeMode = true;
      c.searchYouTube(widget.initialQuery!);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final query = _searchCtrl.text.trim().toLowerCase();
    final localMatches = query.isEmpty
        ? c.tracks
        : c.tracks
            .where((t) =>
                t.title.toLowerCase().contains(query) ||
                t.artist.toLowerCase().contains(query) ||
                (t.album ?? '').toLowerCase().contains(query))
            .toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              RitimHeroBanner(
                palette: p,
                assetPath: 'assets/images/ritim_search_stage.jpg',
                eyebrow: 'CANLI SAHNE & ARŞİV',
                title: 'Ara & Keşfet',
                subtitle:
                    'YouTube üzerinden tek dokunuşla MP3 ses veya HD MP4 video indir, çevrimdışı dinle.',
                icon: Icons.travel_explore_rounded,
                accentColor: p.secondary,
                trailing: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.secondary.withValues(alpha: 0.16),
                    border:
                        Border.all(color: p.secondary.withValues(alpha: 0.42)),
                  ),
                  alignment: Alignment.center,
                  child: PlayingBars(
                    isPlaying: c.isPlaying || c.isSearchingYouTube,
                    color: p.secondary,
                    size: 26,
                    barCount: 4,
                  ),
                ),
                bottom: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _modeTabButton(
                          p,
                          selected: _youtubeMode,
                          icon: Icons.ondemand_video_rounded,
                          label: 'YouTube',
                          onTap: () => setState(() => _youtubeMode = true),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _modeTabButton(
                          p,
                          selected: !_youtubeMode,
                          icon: Icons.library_music_rounded,
                          label: 'Kitaplığım (${c.tracks.length})',
                          onTap: () => setState(() => _youtubeMode = false),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (val) {
                  if (_youtubeMode) c.searchYouTube(val);
                },
                decoration: InputDecoration(
                  hintText: _youtubeMode
                      ? 'YouTube’da sanatçı, şarkı, klip veya konu ara…'
                      : 'Kütüphanede parça, sanatçı, albüm ara…',
                  prefixIcon: Icon(Icons.search_rounded, color: p.primary),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchCtrl.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => setState(() => _searchCtrl.clear()),
                        ),
                      if (_youtubeMode)
                        IconButton(
                          icon: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: p.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: p.background,
                              size: 18,
                            ),
                          ),
                          onPressed: () => c.searchYouTube(_searchCtrl.text),
                        ),
                    ],
                  ),
                  filled: true,
                  fillColor: p.surface.withValues(alpha: 0.92),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide:
                        BorderSide(color: p.primary.withValues(alpha: 0.24)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: p.primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_youtubeMode) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _quickTags.map((tag) {
                      final active =
                          c.lastSearchQuery.toLowerCase() == tag.toLowerCase();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: Icon(
                            Icons.music_note_rounded,
                            size: 15,
                            color: active ? p.background : p.primary,
                          ),
                          label: Text(
                            tag,
                            style: TextStyle(
                              color: active ? p.background : Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          backgroundColor:
                              active ? p.primary : p.surface.withValues(alpha: 0.9),
                          side: BorderSide(
                            color: active
                                ? p.primary
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                          onPressed: () {
                            _searchCtrl.text = tag;
                            c.searchYouTube(tag);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                RitimGlassCard(
                  palette: p,
                  radius: 16,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.high_quality_rounded,
                          color: p.primary, size: 19),
                      const SizedBox(width: 8),
                      Text(
                        'Kalite:',
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Standart'),
                        selected: _quality == DownloadQuality.standard,
                        onSelected: (_) =>
                            setState(() => _quality = DownloadQuality.standard),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('En yüksek'),
                        selected: _quality == DownloadQuality.highest,
                        onSelected: (_) =>
                            setState(() => _quality = DownloadQuality.highest),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: widget.onOpenDownloads,
                        icon: const Icon(Icons.downloading_rounded, size: 16),
                        label: const Text('Kuyruk'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (c.isSearchingYouTube)
                  Padding(
                    padding: const EdgeInsets.all(36),
                    child: Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: p.primary),
                          const SizedBox(height: 12),
                          Text('YouTube sahnesi taranıyor…',
                              style: TextStyle(color: p.muted)),
                        ],
                      ),
                    ),
                  )
                else if (c.searchError != null)
                  RitimGlassCard(
                    palette: p,
                    glowColor: p.coral,
                    child: Text(c.searchError!,
                        style: TextStyle(color: p.coral)),
                  )
                else if (c.searchResults.isEmpty)
                  RitimGlassCard(
                    palette: p,
                    backgroundAsset: 'assets/images/ritim_download_studio.jpg',
                    backgroundOpacity: 0.22,
                    child: Column(
                      children: [
                        Icon(Icons.graphic_eq_rounded,
                            size: 42, color: p.primary),
                        const SizedBox(height: 10),
                        const Text(
                          'Şarkı veya klip ara; her sonucun yanındaki MP3 veya MP4 butonlarıyla anında cihazına kaydet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          '${c.searchResults.length} sonuç · "${c.lastSearchQuery}"',
                          style: TextStyle(
                              color: p.muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          'Tek tık MP3 / MP4',
                          style: TextStyle(
                              color: p.primary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  ...c.searchResults.map((item) => _buildYoutubeRow(p, item)),
                ],
              ] else ...[
                Text(
                  '${localMatches.length} yerel parça',
                  style: TextStyle(color: p.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                ...localMatches.map((t) => TrackRowTile(
                      controller: c,
                      track: t,
                      contextTracks: localMatches,
                      onOpenPlayer: widget.onOpenPlayer,
                    )),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _modeTabButton(
    RitimPalette p, {
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? p.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? p.background : Colors.white70,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? p.background : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYoutubeRow(RitimPalette p, PlaylistItem item) {
    final mp3Dl = c.downloadEntries
        .where((e) =>
            e.sourceURL.contains(item.id) &&
            e.format == DownloadFormat.mp3 &&
            (e.isActive || e.status == DownloadStatus.completed))
        .firstOrNull;
    final mp4Dl = c.downloadEntries
        .where((e) =>
            e.sourceURL.contains(item.id) &&
            e.format == DownloadFormat.mp4 &&
            (e.isActive || e.status == DownloadStatus.completed))
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RitimGlassCard(
        palette: p,
        radius: 18,
        padding: const EdgeInsets.all(11),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Image.network(
                    item.thumbnailUrl,
                    width: 86,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 86,
                      height: 60,
                      color: p.elevated,
                      child: Icon(Icons.music_video_rounded, color: p.primary),
                    ),
                  ),
                  if (item.duration != null && item.duration! > 0)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          formatClock(item.duration!),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.3),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _formatDownloadAction(
                  p: p,
                  item: item,
                  format: DownloadFormat.mp3,
                  dl: mp3Dl,
                  label: 'MP3',
                  icon: Icons.audiotrack_rounded,
                  accent: p.primary,
                ),
                const SizedBox(height: 6),
                _formatDownloadAction(
                  p: p,
                  item: item,
                  format: DownloadFormat.mp4,
                  dl: mp4Dl,
                  label: 'MP4',
                  icon: Icons.videocam_rounded,
                  accent: p.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatDownloadAction({
    required RitimPalette p,
    required PlaylistItem item,
    required DownloadFormat format,
    required DownloadEntry? dl,
    required String label,
    required IconData icon,
    required Color accent,
  }) {
    if (dl != null && dl.isActive) {
      return Container(
        width: 66,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                value: dl.progress > 0.06 ? dl.progress : null,
                strokeWidth: 2,
                color: accent,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '${(dl.progress * 100).round()}%',
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    if (dl != null && dl.status == DownloadStatus.completed) {
      return GestureDetector(
        onTap: () {
          final match = c.tracks.where((t) => t.id == dl.trackID).firstOrNull;
          if (match != null) {
            c.playTrack(match, context: c.tracks);
            if (match.kind == MediaKind.video && widget.onOpenPlayer != null) {
              widget.onOpenPlayer!();
            }
          }
        },
        child: Container(
          width: 66,
          height: 28,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, size: 15, color: p.background),
              const SizedBox(width: 2),
              Text(
                'ÇAL',
                style: TextStyle(
                  color: p.background,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RitimPress(
      onTap: () {
        c.enqueueDownload(
          item.url,
          format: format,
          quality: _quality,
          title: item.title,
          artist: item.artist,
        );
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1600),
            content: Text('“${item.title}” $label olarak indiriliyor…'),
          ),
        );
      },
      child: Container(
        width: 66,
        height: 28,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: accent.withValues(alpha: 0.48)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
