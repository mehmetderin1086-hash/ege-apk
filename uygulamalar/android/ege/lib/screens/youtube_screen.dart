import 'package:flutter/material.dart';

import '../services/device_bridge.dart';
import '../services/work_hub.dart';
import '../services/youtube_service.dart';
import '../state/jarvis_controller.dart';
import '../widgets/jarvis_ui.dart';

String _mmss(int ms) {
  final s = (ms / 1000).floor();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// In-app YouTube search + music player (Windows Ege YouTube panel port).
class YoutubeScreen extends StatefulWidget {
  final JarvisController controller;

  const YoutubeScreen({super.key, required this.controller});

  @override
  State<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends State<YoutubeScreen> {
  late final TextEditingController _q = TextEditingController(text: widget.controller.ytQuery);

  JarvisController get c => widget.controller;

  static const _ideas = ['Türkçe pop', 'Tarkan', 'Sezen Aksu', 'lofi çalışma müziği', 'Barış Manço', 'klasik müzik', 'podcast'];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search([String? text]) async {
    final q = (text ?? _q.text).trim();
    if (q.isEmpty) return;
    _q.text = q;
    FocusScope.of(context).unfocus();
    await c.searchYoutube(q);
  }

  Future<void> _download(YtVideo v, {required bool video}) async {
    await c.startWork(video ? WorkKind.video : WorkKind.audio, v.url);
    if (mounted) {
      showJarvisSnack(context, '${video ? 'Video' : 'Ses'} indirme Çalışmalar\'da başladı: ${v.title}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('YouTube Müzik')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Şarkı, sanatçı, podcast…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _search),
                  ),
                ),
              ),
              if (c.musicNow != null) NowPlayingCard(controller: c),
              if (c.ytSearching) const LinearProgressIndicator(minHeight: 2),
              if (c.ytError != null)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(c.ytError!, style:  TextStyle(color: JColors.bad)),
                ),
              Expanded(
                child: c.ytResults.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          const Icon(Icons.smart_display_rounded, size: 50, color: Color(0xFFF472B6)),
                          const SizedBox(height: 8),
                           Text(
                            'Ara ve Ege içinde dinle. Sesle de olur: "YouTube\'da Tarkan çal", '
                            '"müziği duraklat", "sıradaki şarkı".',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: JColors.muted, height: 1.45),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final i in _ideas) ActionChip(label: Text(i), onPressed: () => _search(i)),
                            ],
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: c.ytResults.length,
                        itemBuilder: (ctx, i) {
                          final v = c.ytResults[i];
                          final playing = c.musicNow?.id == v.id;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 88,
                                height: 50,
                                child: v.thumbUrl.isEmpty
                                    ? Container(color: JColors.surfaceHi)
                                    : Image.network(
                                        v.thumbUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          color: JColors.surfaceHi,
                                          child: const Icon(Icons.music_note_rounded),
                                        ),
                                      ),
                              ),
                            ),
                            title: Text(
                              v.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: playing ? FontWeight.w800 : FontWeight.w500,
                                color: playing ? JColors.accent : JColors.text,
                              ),
                            ),
                            subtitle: Text(
                              '${v.author}${v.durationLabel.isEmpty ? '' : ' • ${v.durationLabel}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:  TextStyle(fontSize: 11.5, color: JColors.dim),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (val) async {
                                switch (val) {
                                  case 'audio':
                                    await _download(v, video: false);
                                  case 'video':
                                    await _download(v, video: true);
                                  case 'open':
                                    await DeviceBridge.openUrl(v.url);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'audio', child: Text('🎵 Sesi indir (m4a)')),
                                PopupMenuItem(value: 'video', child: Text('🎬 Videoyu indir (mp4)')),
                                PopupMenuItem(value: 'open', child: Text('YouTube uygulamasında aç')),
                              ],
                            ),
                            onTap: () async {
                              final msg = await c.playVideo(v, queue: c.ytResults);
                              if (context.mounted && msg.startsWith('Ses akışı')) {
                                showJarvisSnack(context, msg, error: true);
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class NowPlayingCard extends StatelessWidget {
  final JarvisController controller;

  const NowPlayingCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final v = c.musicNow!;
    final st = c.musicStatus;
    final pos = (st['positionMs'] as num?)?.toInt() ?? 0;
    final dur = (st['durationMs'] as num?)?.toInt() ?? 0;
    final state = c.musicState;
    final playing = state == 'playing';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: GlassCard(
        glow: const Color(0xFFF472B6),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.graphic_eq_rounded, color: Color(0xFFF472B6)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                        c.musicError ??
                            (state == 'preparing' ? 'Yükleniyor…' : '${v.author} • ${_mmss(pos)} / ${_mmss(dur)}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: c.musicError != null ? JColors.bad : JColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (dur > 0)
              Slider(
                value: pos.clamp(0, dur).toDouble(),
                max: dur.toDouble(),
                onChanged: (x) => DeviceBridge.streamSeek(x.round()),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(onPressed: c.previousTrack, icon: const Icon(Icons.skip_previous_rounded)),
                IconButton.filled(
                  onPressed: state == 'preparing' ? null : (playing ? c.pauseMusic : c.resumeMusic),
                  icon: state == 'preparing'
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                IconButton(onPressed: c.nextTrack, icon: const Icon(Icons.skip_next_rounded)),
                IconButton(onPressed: c.stopMusic, icon: const Icon(Icons.stop_rounded)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small persistent player shown above the bottom navigation.
class MiniPlayerBar extends StatelessWidget {
  final JarvisController controller;

  const MiniPlayerBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final v = c.musicNow;
    if (v == null) return const SizedBox.shrink();
    final state = c.musicState;
    final playing = state == 'playing';
    final pos = (c.musicStatus['positionMs'] as num?)?.toInt() ?? 0;
    final dur = (c.musicStatus['durationMs'] as num?)?.toInt() ?? 0;
    return Material(
      color: const Color(0xFF0E1A30),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => YoutubeScreen(controller: c))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              minHeight: 2,
              value: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : (state == 'preparing' ? null : 0),
              color: const Color(0xFFF472B6),
              backgroundColor: Colors.transparent,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  const Icon(Icons.music_note_rounded, size: 18, color: Color(0xFFF472B6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: state == 'preparing' ? null : (playing ? c.pauseMusic : c.resumeMusic),
                    icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: c.nextTrack, icon: const Icon(Icons.skip_next_rounded)),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: c.stopMusic, icon: const Icon(Icons.close_rounded, size: 18)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
