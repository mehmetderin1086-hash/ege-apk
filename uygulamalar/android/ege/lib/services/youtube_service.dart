import 'dart:async';
import 'dart:typed_data';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// A YouTube search hit (Windows JARVIS /yt-search equivalent).
class YtVideo {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbUrl;

  const YtVideo({
    required this.id,
    required this.title,
    this.author = '',
    this.duration,
    this.thumbUrl = '',
  });

  String get url => 'https://www.youtube.com/watch?v=$id';

  String get durationLabel {
    final d = duration;
    if (d == null) return '';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'durationSec': duration?.inSeconds,
        'thumbUrl': thumbUrl,
      };

  factory YtVideo.fromJson(Map<String, dynamic> j) => YtVideo(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        author: j['author']?.toString() ?? '',
        duration: j['durationSec'] is num ? Duration(seconds: (j['durationSec'] as num).toInt()) : null,
        thumbUrl: j['thumbUrl']?.toString() ?? '',
      );
}

/// Key-less YouTube search, in-app audio streaming and audio/video download.
class YoutubeService {
  static final _idRe = RegExp(r'(?:v=|youtu\.be/|shorts/|embed/)([A-Za-z0-9_-]{11})');

  static String? videoIdFrom(String urlOrId) {
    final t = urlOrId.trim();
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(t)) return t;
    return _idRe.firstMatch(t)?.group(1);
  }

  static bool isYoutubeUrl(String s) =>
      RegExp(r'(youtube\.com|youtu\.be)/', caseSensitive: false).hasMatch(s);

  static Future<List<YtVideo>> search(String query, {int limit = 15}) async {
    final yt = YoutubeExplode();
    try {
      final res = await yt.search.search(query).timeout(const Duration(seconds: 25));
      return res
          .take(limit)
          .map((v) => YtVideo(
                id: v.id.value,
                title: v.title,
                author: v.author,
                duration: v.duration,
                thumbUrl: v.thumbnails.mediumResUrl,
              ))
          .toList();
    } finally {
      yt.close();
    }
  }

  static Future<YtVideo> info(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final v = await yt.videos.get(videoId).timeout(const Duration(seconds: 25));
      return YtVideo(
        id: v.id.value,
        title: v.title,
        author: v.author,
        duration: v.duration,
        thumbUrl: v.thumbnails.mediumResUrl,
      );
    } finally {
      yt.close();
    }
  }

  /// Best audio-only stream (prefers MP4/M4A which every Android plays).
  static Future<({String url, String ext, int bytes})> audioStream(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final m = await yt.videos.streams.getManifest(videoId).timeout(const Duration(seconds: 30));
      final mp4 = m.audioOnly.where((s) => s.container == StreamContainer.mp4).toList();
      final s = mp4.isNotEmpty ? mp4.withHighestBitrate() : m.audioOnly.withHighestBitrate();
      return (
        url: s.url.toString(),
        ext: s.container == StreamContainer.mp4 ? 'm4a' : s.container.name,
        bytes: s.size.totalBytes,
      );
    } finally {
      yt.close();
    }
  }

  /// Downloads audio or (muxed) video bytes through youtube_explode's chunked
  /// stream client (avoids YouTube throttling of plain GET requests).
  static Future<({Uint8List bytes, String ext, String title})> download(
    String videoId, {
    bool video = false,
    int maxBytes = 300 * 1024 * 1024,
    void Function(double progress)? onProgress,
  }) async {
    final yt = YoutubeExplode();
    try {
      final meta = await yt.videos.get(videoId).timeout(const Duration(seconds: 25));
      final m = await yt.videos.streams.getManifest(videoId).timeout(const Duration(seconds: 30));
      StreamInfo info;
      String ext;
      if (video) {
        if (m.muxed.isEmpty) throw StateError('Bu video için birleşik (ses+görüntü) akış bulunamadı.');
        final mp4 = m.muxed.where((s) => s.container == StreamContainer.mp4).toList();
        info = mp4.isNotEmpty ? mp4.withHighestBitrate() : m.muxed.withHighestBitrate();
        ext = 'mp4';
      } else {
        final mp4 = m.audioOnly.where((s) => s.container == StreamContainer.mp4).toList();
        info = mp4.isNotEmpty ? mp4.withHighestBitrate() : m.audioOnly.withHighestBitrate();
        ext = info.container == StreamContainer.mp4 ? 'm4a' : info.container.name;
      }
      final total = info.size.totalBytes;
      if (total > maxBytes) {
        throw StateError('Dosya çok büyük (${(total / 1048576).toStringAsFixed(0)} MB).');
      }
      final builder = BytesBuilder(copy: false);
      var got = 0;
      await for (final chunk in yt.videos.streams.get(info).timeout(const Duration(minutes: 2))) {
        builder.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call((got / total).clamp(0, 1).toDouble());
      }
      return (bytes: builder.takeBytes(), ext: ext, title: meta.title);
    } finally {
      yt.close();
    }
  }
}
