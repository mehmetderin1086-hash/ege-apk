import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../ritim_ai_service.dart';
import '../ritim_models.dart';
import '../ritim_store.dart';
import '../theme_design.dart';
import 'shared_widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.controller,
    required this.onOpenSearch,
    required this.onOpenLibrary,
    required this.onOpenDownloads,
    required this.onOpenAssistant,
    required this.onOpenPlayer,
  });

  final RitimController controller;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenPlayer;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _period = 7;
  String? _selectedDayKey;

  RitimController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final p = c.palette;
    final todaySeconds = c.totalSecondsForDays(1);
    final weekSeconds = c.totalSecondsForDays(7);
    final periodSeconds = c.totalSecondsForDays(_period);
    final chartDays = c.recentDays(_period);
    final selectedDay = chartDays.firstWhere(
      (d) => d.dayKey == _selectedDayKey,
      orElse: () => chartDays.last,
    );
    final favorites = c.tracks.where((t) => t.isFavorite).toList();
    final audioCount = c.tracks.where((t) => t.kind == MediaKind.audio).length;
    final videoCount = c.tracks.where((t) => t.kind == MediaKind.video).length;
    final activeDownloads = c.downloadEntries.where((e) => e.isActive).length;
    final mostPlayed = c.tracks.where((t) => t.playCount > 0).toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    final recent = c.tracks.where((t) => t.lastPlayedAt != null).toList()
      ..sort((a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!));

    return RefreshIndicator(
      color: p.primary,
      onRefresh: () => c.rescanAllMetadata(),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildHeader(p),
                const SizedBox(height: 16),
                if (c.currentTrack != null) ...[
                  _buildContinueCard(p, c.currentTrack!),
                  const SizedBox(height: 16),
                ],
                _buildHeroCard(p, todaySeconds, weekSeconds),
                const SizedBox(height: 18),
                _buildQuickActions(p, activeDownloads: activeDownloads),
                const SizedBox(height: 18),
                _buildSmartCollectionsShelf(p),
                const SizedBox(height: 18),
                _buildListeningCard(p, periodSeconds, chartDays, selectedDay),
                const SizedBox(height: 18),
                _buildDailyMixCard(p),
                const SizedBox(height: 18),
                _buildLibraryMetrics(
                  p,
                  audioCount: audioCount,
                  videoCount: videoCount,
                  favoritesCount: favorites.length,
                  activeDownloads: activeDownloads,
                ),
                const SizedBox(height: 18),
                if (mostPlayed.isNotEmpty) ...[
                  _sectionHeader(p, 'Sık döndüğün parçalar', 'En çok çalınanlar'),
                  const SizedBox(height: 10),
                  ...mostPlayed.take(3).map((t) => TrackRowTile(
                        controller: c,
                        track: t,
                        contextTracks: mostPlayed,
                        onOpenPlayer: widget.onOpenPlayer,
                      )),
                  const SizedBox(height: 14),
                ],
                if (recent.isNotEmpty) ...[
                  _sectionHeader(p, 'Yeniden buluşalım', 'Son çaldıkların'),
                  const SizedBox(height: 10),
                  ...recent.take(4).map((t) => TrackRowTile(
                        controller: c,
                        track: t,
                        contextTracks: recent,
                        onOpenPlayer: widget.onOpenPlayer,
                      )),
                ] else if (c.tracks.isNotEmpty) ...[
                  _sectionHeader(p, 'İlk ritmini seç', 'Kütüphanenden'),
                  const SizedBox(height: 10),
                  ...c.tracks.take(3).map((t) => TrackRowTile(
                        controller: c,
                        track: t,
                        contextTracks: c.tracks,
                        onOpenPlayer: widget.onOpenPlayer,
                      )),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone_android_rounded, size: 14, color: p.muted),
                    const SizedBox(width: 6),
                    Text(
                      'Müziklerin ve istatistiklerin bu cihazda.',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(RitimPalette p) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KİŞİSEL ALANIN',
                style: TextStyle(
                  color: p.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Text(
                    'ritim',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.4,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                      border:
                          Border.all(color: p.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      c.themeStyle.title,
                      style: TextStyle(
                        color: p.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () async {
            await c.cycleWallpaper();
            if (mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(milliseconds: 1200),
                  content: Text('Arka plan: ${c.wallpaper.title}'),
                ),
              );
            }
          },
          style: IconButton.styleFrom(
            backgroundColor: p.surface.withValues(alpha: 0.9),
            fixedSize: const Size(44, 44),
            side: BorderSide(color: p.primary.withValues(alpha: 0.28)),
          ),
          icon: Icon(Icons.wallpaper_rounded, color: p.primary, size: 20),
          tooltip: 'Arka Plan Değiştir',
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => showRitimSettingsSheet(context, c),
          style: IconButton.styleFrom(
            backgroundColor: p.surface.withValues(alpha: 0.9),
            fixedSize: const Size(44, 44),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
          icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 21),
          tooltip: 'Ayarlar',
        ),
      ],
    );
  }

  Widget _buildContinueCard(RitimPalette p, MediaTrack current) {
    return RitimGlassCard(
      palette: p,
      radius: 18,
      glowColor: p.primary,
      onTap: widget.onOpenPlayer,
      child: Row(
        children: [
          RitimCoverArt(
            palette: p,
            colorIndex: current.colorIndex,
            artworkPath: c.artworkPathFor(current),
            isVideo: current.kind == MediaKind.video,
            size: 52,
            radius: 12,
            isPlaying: c.isPlaying,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KALDIĞIN YERDEN',
                  style: TextStyle(
                    color: p.primary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  current.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  '${current.artist} · ${formatClock(c.elapsed)} / ${formatClock(c.duration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: c.togglePlayPause,
            style: FilledButton.styleFrom(
              backgroundColor: p.primary,
              foregroundColor: p.background,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(11),
              minimumSize: Size.zero,
            ),
            child: Icon(
              c.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(
    RitimPalette p,
    double todaySeconds,
    double weekSeconds,
  ) {
    final now = DateTime.now();
    const months = [
      '',
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara'
    ];
    final dateLabel = '${now.day} ${months[now.month]}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: p.primary.withValues(alpha: 0.25)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/ritim_lounge_backdrop.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(color: p.surface),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      p.background.withValues(alpha: 0.78),
                      p.surface.withValues(alpha: 0.88),
                      p.background.withValues(alpha: 0.94),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: p.primary, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'BUGÜNÜN RİTMİ',
                        style: TextStyle(
                          color: p.primary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatDurationHuman(todaySeconds),
                              style: const TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.2,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              todaySeconds > 0
                                  ? 'bugün müziğe ayırdığın zaman'
                                  : 'Bugün ritmini başlat.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: widget.onOpenPlayer,
                        child: RitimSpinningVinyl(
                          palette: p,
                          isPlaying: c.isPlaying,
                          artworkPath: c.currentTrack != null
                              ? c.artworkPathFor(c.currentTrack!)
                              : null,
                          colorIndex: c.currentTrack?.colorIndex ?? 0,
                          size: 88,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SON 7 GÜN',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.56),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatDurationHuman(weekSeconds),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (c.tracks.length > 1) ...[
                        OutlinedButton.icon(
                          onPressed: () {
                            final shuffled = List<MediaTrack>.from(c.tracks)
                              ..shuffle();
                            c.shuffleEnabled = true;
                            c.playTrack(shuffled.first, context: shuffled);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.24)),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          icon: const Icon(Icons.shuffle_rounded, size: 17),
                          label: const Text('Karıştır',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton.icon(
                        onPressed: () {
                          if (c.currentTrack != null) {
                            c.togglePlayPause();
                          } else if (c.tracks.isNotEmpty) {
                            c.playTrack(c.tracks.first, context: c.tracks);
                          } else {
                            c.pickAndImportLocalFiles();
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: p.primary,
                          foregroundColor: p.background,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: const StadiumBorder(),
                        ),
                        icon: Icon(
                          c.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 20,
                        ),
                        label: Text(
                          c.isPlaying
                              ? 'Duraklat'
                              : (c.tracks.isEmpty ? 'Parça Ekle' : 'Çal'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartCollectionsShelf(RitimPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(p, 'Sana özel raflar', 'Akıllı koleksiyonlar'),
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: SmartCollection.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final sc = SmartCollection.values[i];
              final items = sc.tracksIn(c.tracks);
              final accent = [p.primary, p.secondary, p.coral, p.primary][i];
              const shelfAssets = [
                'assets/images/ritim_search_stage.jpg',
                'assets/images/ritim_download_studio.jpg',
                'assets/images/ritim_library_vinyl.jpg',
                'assets/images/ritim_night_drive_bg.jpg',
              ];
              return SizedBox(
                width: 224,
                child: RitimGlassCard(
                  palette: p,
                  radius: 18,
                  padding: const EdgeInsets.all(13),
                  glowColor: accent,
                  backgroundAsset: shelfAssets[i % shelfAssets.length],
                  backgroundOpacity: 0.26,
                  onTap: () => _openSmartCollectionSheet(sc, items),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(sc.icon, color: accent, size: 18),
                          const Spacer(),
                          Text(
                            '${items.length}',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        sc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      Text(
                        sc.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListeningCard(
    RitimPalette p,
    double periodSeconds,
    List<ListeningDay> chartDays,
    ListeningDay selectedDay,
  ) {
    final peak = math.max(
      1.0,
      chartDays.map((d) => d.seconds).fold<double>(0, math.max),
    );
    const weekdays = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

    return RitimGlassCard(
      palette: p,
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Dinleme ritmin',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: p.background.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  children: [7, 30].map((d) {
                    final sel = _period == d;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _period = d;
                        _selectedDayKey = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? p.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '$d gün',
                          style: TextStyle(
                            color: sel ? p.background : p.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatDurationHuman(periodSeconds),
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              Text('toplam', style: TextStyle(color: p.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 112,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: chartDays.map((day) {
                final sel = day.dayKey == selectedDay.dayKey;
                final frac = day.seconds > 0
                    ? math.max(0.08, day.seconds / peak)
                    : 0.03;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDayKey = day.dayKey),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: _period == 7 ? 5 : 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            height: 100 * frac,
                            decoration: BoxDecoration(
                              color: day.seconds == 0
                                  ? p.elevated
                                  : (sel
                                      ? p.primary
                                      : p.secondary.withValues(alpha: 0.78)),
                              borderRadius:
                                  BorderRadius.circular(_period == 7 ? 6 : 3),
                              boxShadow: sel && day.seconds > 0
                                  ? [
                                      BoxShadow(
                                        color:
                                            p.primary.withValues(alpha: 0.45),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (_period == 7) ...[
            const SizedBox(height: 6),
            Row(
              children: chartDays.map((day) {
                final isToday = day.dayKey == chartDays.last.dayKey;
                return Expanded(
                  child: Text(
                    weekdays[day.date.weekday],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isToday ? p.primary : p.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 10),
          if (periodSeconds == 0)
            Text(
              'Henüz dinleme kaydı yok. Süreler gerçekten çaldığın zamanla oluşur.',
              style: TextStyle(color: p.muted, fontSize: 12),
            )
          else
            Row(
              children: [
                Text(selectedDay.dayKey,
                    style: TextStyle(color: p.muted, fontSize: 12)),
                const Spacer(),
                Text(
                  formatDurationHuman(selectedDay.seconds),
                  style: TextStyle(
                      color: p.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDailyMixCard(RitimPalette p) {
    final mix = c.dailyMix;
    final dayPart = AIDayPart.forNow();
    return RitimGlassCard(
      palette: p,
      radius: 20,
      glowColor: p.secondary,
      backgroundAsset: 'assets/images/ritim_ai_dj_deck.jpg',
      backgroundOpacity: 0.28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: p.secondary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GÜNÜN KARIŞIMI · ${dayPart.greeting.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              TextButton(
                onPressed: c.isDailyLoading
                    ? null
                    : () {
                        if (c.aiConfig.selectedModelId.isEmpty) {
                          widget.onOpenAssistant();
                        } else {
                          c.generateDailyMix();
                        }
                      },
                child: c.isDailyLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(mix == null ? 'Asistanı Aç' : 'Yenile'),
              ),
            ],
          ),
          if (mix != null) ...[
            Text(mix.title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(mix.note, style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () {
                final list = mix.trackIDs
                    .map((id) =>
                        c.tracks.where((t) => t.id == id).firstOrNull)
                    .whereType<MediaTrack>()
                    .toList();
                if (list.isNotEmpty) {
                  c.playTrack(list.first, context: list);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: p.secondary,
                foregroundColor: p.background,
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text('${mix.trackIDs.length} Parçayı Çal'),
            ),
          ] else ...[
            Text(
              'Ruh hâline ve günün saatine göre AI karışımı hazırlamak için CLIProxyAPI asistanını bağla.',
              style: TextStyle(color: p.muted, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions(RitimPalette p, {required int activeDownloads}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(p, 'Stüdyo sahneleri', 'Hızlı işlem butonları'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: RitimImageActionButton(
                palette: p,
                assetPath: 'assets/images/ritim_download_studio.jpg',
                title: 'MP3 & MP4',
                subtitle: 'YouTube ses & video',
                icon: Icons.downloading_rounded,
                accentColor: p.primary,
                badge: activeDownloads > 0 ? '$activeDownloads aktif' : 'İndir',
                onTap: widget.onOpenDownloads,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RitimImageActionButton(
                palette: p,
                assetPath: 'assets/images/ritim_search_stage.jpg',
                title: 'YouTube Ara',
                subtitle: 'Şarkı & klip bul',
                icon: Icons.travel_explore_rounded,
                accentColor: p.secondary,
                badge: 'Keşfet',
                onTap: widget.onOpenSearch,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: RitimImageActionButton(
                palette: p,
                assetPath: 'assets/images/ritim_library_vinyl.jpg',
                title: 'Dosya Ekle',
                subtitle: 'MP3, M4A, MP4 seç',
                icon: Icons.album_rounded,
                accentColor: p.coral,
                badge: '${c.tracks.length} kayıt',
                onTap: () => c.pickAndImportLocalFiles(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RitimImageActionButton(
                palette: p,
                assetPath: 'assets/images/ritim_ai_dj_deck.jpg',
                title: 'AI DJ Stüdyo',
                subtitle: 'Akıllı set hazırla',
                icon: Icons.auto_awesome_rounded,
                accentColor: p.primary,
                badge: 'CLIProxy',
                onTap: widget.onOpenAssistant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLibraryMetrics(
    RitimPalette p, {
    required int audioCount,
    required int videoCount,
    required int favoritesCount,
    required int activeDownloads,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(p, 'Kütüphanene bir bakış', 'Cihazında'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _metricTile(
              p,
              title: 'Tüm parçalar',
              value: '${c.tracks.length}',
              detail: '${c.playlists.length} çalma listesi',
              icon: Icons.layers_rounded,
              color: p.primary,
            ),
            _metricTile(
              p,
              title: 'Favoriler',
              value: '$favoritesCount',
              detail: favoritesCount > 0 ? 'Beğendiğin ritimler' : 'Henüz yok',
              icon: Icons.favorite_rounded,
              color: p.coral,
            ),
            _metricTile(
              p,
              title: 'Ses / Video',
              value: '$audioCount / $videoCount',
              detail: 'Çevrimdışı hazır',
              icon: Icons.perm_media_rounded,
              color: p.secondary,
            ),
            _metricTile(
              p,
              title: 'İndirmeler',
              value: '$activeDownloads',
              detail: activeDownloads > 0 ? 'Kuyruk aktif' : 'Tamamlandı',
              icon: Icons.downloading_rounded,
              color: p.primary,
              onTap: widget.onOpenDownloads,
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricTile(
    RitimPalette p, {
    required String title,
    required String value,
    required String detail,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return RitimGlassCard(
      palette: p,
      radius: 18,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Text(detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _sectionHeader(RitimPalette p, String title, String caption) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption.toUpperCase(),
          style: TextStyle(
            color: p.muted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ],
    );
  }

  void _openSmartCollectionSheet(
    SmartCollection collection,
    List<MediaTrack> items,
  ) {
    final p = c.palette;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(collection.icon, color: p.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(collection.title,
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.bold)),
                    ),
                    if (items.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          c.createPlaylist(
                            collection.title,
                            trackIds: items.map((e) => e.id).toList(),
                            detail: collection.detail,
                          );
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    '“${collection.title}” çalma listesi olarak kaydedildi.')),
                          );
                        },
                        icon: const Icon(Icons.playlist_add_rounded, size: 18),
                        label: const Text('Kaydet'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(collection.detail,
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text('Bu koleksiyonda henüz parça yok.',
                          style: TextStyle(color: p.muted)),
                    ),
                  )
                else ...[
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
                    child: ListView(
                      children: items
                          .map((t) => TrackRowTile(
                                controller: c,
                                track: t,
                                contextTracks: items,
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
