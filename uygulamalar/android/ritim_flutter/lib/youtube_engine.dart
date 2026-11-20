import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'ritim_models.dart';

class ResolvedMediaStream {
  const ResolvedMediaStream({
    required this.url,
    required this.headers,
    required this.fileExtension,
    required this.bitrate,
    this.contentLength = 0,
    this.itag,
    this.resolution,
    this.includesAudio = true,
    this.requiresRange = false,
  });

  final Uri url;
  final Map<String, String> headers;
  final String fileExtension;
  final int bitrate;
  final int contentLength;
  final int? itag;
  final int? resolution;
  final bool includesAudio;
  final bool requiresRange;
}

class ResolvedYouTubeMedia {
  const ResolvedYouTubeMedia({
    this.videoId,
    required this.title,
    required this.artist,
    required this.audio,
    this.adaptiveAudio,
    this.adaptiveVideo,
    this.muxedVideo,
    this.video,
    this.actualResolution,
    this.sourceHighestResolution,
    required this.sourceAudioBitrate,
    this.durationSeconds = 0,
  });

  final String? videoId;
  final String title;
  final String artist;
  final ResolvedMediaStream audio;
  final ResolvedMediaStream? adaptiveAudio;
  final ResolvedMediaStream? adaptiveVideo;
  final ResolvedMediaStream? muxedVideo;
  final ResolvedMediaStream? video;
  final int? actualResolution;
  final int? sourceHighestResolution;
  final int sourceAudioBitrate;
  final double durationSeconds;

  String? get thumbnailUrl => (videoId != null && videoId!.isNotEmpty)
      ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg'
      : null;

  String? get qualityNote {
    if (actualResolution != null &&
        sourceHighestResolution != null &&
        sourceHighestResolution! > actualResolution!) {
      return 'Cihaza uygun akış: ${actualResolution}p.';
    }
    return null;
  }
}

class _FatalMediaException implements Exception {
  const _FatalMediaException(this.message);
  final String message;
}

/// Ritim NativeYouTubeCatalog: YouTube arama, oEmbed ve çalma listesi çözümleyici.
class NativeYouTubeCatalog {
  NativeYouTubeCatalog({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  Future<List<PlaylistItem>> search(String query, {int limit = 50}) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      throw const RitimException('Aramak için sanatçı, parça veya konu yaz.');
    }
    final uri =
        Uri.https('www.youtube.com', '/results', {'search_query': clean});
    final html = await _getString(uri);
    final initial = extractInitialData(html);
    if (initial == null) {
      throw const RitimException('YouTube arama sonuçları okunamadı.');
    }
    final found = <PlaylistItem>[];
    final seen = <String>{};
    _collectRenderers(initial, const ['videoRenderer', 'compactVideoRenderer'],
        (map) {
      if (found.length >= limit) return;
      final item = _parseRenderer(map, index: found.length);
      if (item != null && seen.add(item.id)) {
        found.add(item);
      }
    });
    if (found.isEmpty) {
      throw const RitimException('Bu arama için indirilebilir YouTube sonucu bulunamadı.');
    }
    return found;
  }

  Future<({String title, String artist})?> fetchOEmbed(Uri videoUrl) async {
    try {
      final uri = Uri.https('www.youtube.com', '/oembed', {
        'url': videoUrl.toString(),
        'format': 'json',
      });
      final resp = await _client
          .get(uri, headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final obj = jsonDecode(resp.body);
      if (obj is! Map<String, dynamic>) return null;
      final title = (obj['title'] as String?)?.trim() ?? '';
      final artist = (obj['author_name'] as String?)?.trim() ?? '';
      if (title.isEmpty && artist.isEmpty) return null;
      return (title: title, artist: artist);
    } catch (_) {
      return null;
    }
  }

  Future<PlaylistPreview> previewPlaylist(
    Uri playlistUrl, {
    int limit = 100,
  }) async {
    final cleanUrl = MediaURLPolicy.validatedPlaylist(playlistUrl.toString());
    final id = cleanUrl.queryParameters['list'] ?? '';
    final isMix = id.startsWith('RD');
    final html = await _getString(cleanUrl);
    final initial = extractInitialData(html);
    if (initial == null) {
      throw const RitimException('YouTube liste sayfası okunamadı.');
    }
    final clientVersion = _extractClientVersion(html) ?? '2.20261023.01.00';

    var root = _findPlaylistRoot(initial) ?? initial;
    final title = _extractPlaylistTitle(initial) ?? 'YouTube Listesi';
    final result = <PlaylistItem>[];
    final seen = <String>{};
    final tokens = <String>{};
    var skipped = 0;
    var truncated = false;

    for (var round = 0; round < 10; round++) {
      final batch = <Map<String, dynamic>>[];
      _collectRenderers(
        root,
        const ['playlistVideoRenderer', 'playlistPanelVideoRenderer'],
        batch.add,
      );
      var added = 0;
      for (final map in batch) {
        final item = _parseRenderer(map, index: result.length);
        if (item == null) {
          skipped++;
          continue;
        }
        if (!seen.add(item.id)) {
          skipped++;
          continue;
        }
        if (result.length >= limit) {
          truncated = true;
          break;
        }
        result.add(item);
        added++;
      }
      if (result.length >= limit) {
        truncated = true;
        break;
      }
      if (isMix && added == 0) break;
      if (isMix && result.isNotEmpty) {
        final next = await _postApi('next', {
          'playlistId': id,
          'videoId': result.last.id,
          'index': result.length - 1,
        }, version: clientVersion);
        final panel = _findPlaylistRoot(next);
        if (panel == null) break;
        root = panel;
      } else {
        final cont = _findContinuation(root);
        if (cont == null || !tokens.add(cont)) break;
        root = await _postApi(
          'browse',
          {'continuation': cont},
          version: clientVersion,
        );
      }
    }

    if (result.isEmpty) {
      throw const RitimException(
          'YouTube bu listeyi göstermedi. Liste herkese açık olmalı; bağlantıyı kontrol edip yeniden dene.');
    }
    if (isMix) truncated = true;
    return PlaylistPreview(
      id: id,
      title: title,
      items: result,
      skipped: skipped,
      truncated: truncated,
    );
  }

  Future<String> _getString(Uri uri) async {
    final resp = await _client.get(uri, headers: {
      'User-Agent': _ua,
      'Accept-Language': 'en-US,en;q=0.9',
      'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
    }).timeout(const Duration(seconds: 25));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw RitimException('YouTube yanıt vermedi (${resp.statusCode}).');
    }
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  Future<Map<String, dynamic>> _postApi(
    String name,
    Map<String, dynamic> body, {
    required String version,
  }) async {
    final payload = Map<String, dynamic>.from(body)
      ..['context'] = {
        'client': {
          'clientName': 'WEB',
          'clientVersion': version,
          'hl': 'en',
          'gl': 'TR',
        },
      };
    final resp = await _client
        .post(
          Uri.https('www.youtube.com', '/youtubei/v1/$name'),
          headers: {
            'User-Agent': _ua,
            'Content-Type': 'application/json',
            'X-Youtube-Client-Name': '1',
            'X-Youtube-Client-Version': version,
            'Accept-Language': 'en-US,en;q=0.9',
            'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 25));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw const RitimException('YouTube liste API yanıt vermedi.');
    }
    final parsed =
        jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
    if (parsed is! Map<String, dynamic>) {
      throw const RitimException('YouTube liste yanıtı okunamadı.');
    }
    return parsed;
  }

  static Map<String, dynamic>? extractInitialData(String html) {
    for (final marker in const [
      'var ytInitialData =',
      'ytInitialData =',
      'window["ytInitialData"] =',
    ]) {
      final idx = html.indexOf(marker);
      if (idx < 0) continue;
      final braceStart = html.indexOf('{', idx + marker.length);
      if (braceStart < 0) continue;
      final slice = _extractJsonObjectSlice(html, braceStart);
      if (slice == null) continue;
      try {
        final obj = jsonDecode(slice);
        if (obj is Map<String, dynamic>) return obj;
      } catch (_) {}
    }
    return null;
  }

  static String? _extractJsonObjectSlice(String src, int start) {
    var depth = 0;
    var inQuote = false;
    var escape = false;
    for (var i = start; i < src.length; i++) {
      final ch = src.codeUnitAt(i);
      if (inQuote) {
        if (escape) {
          escape = false;
        } else if (ch == 92) {
          escape = true;
        } else if (ch == 34) {
          inQuote = false;
        }
      } else if (ch == 34) {
        inQuote = true;
      } else if (ch == 123) {
        depth++;
      } else if (ch == 125) {
        depth--;
        if (depth == 0) {
          return src.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  static String? _extractClientVersion(String html) {
    final m =
        RegExp(r'"INNERTUBE_CLIENT_VERSION"\s*:\s*"([^"]+)"').firstMatch(html);
    return m?.group(1);
  }

  static void _collectRenderers(
    dynamic node,
    List<String> keys,
    void Function(Map<String, dynamic>) onMatch,
  ) {
    if (node is Map) {
      for (final k in keys) {
        final v = node[k];
        if (v is Map<String, dynamic>) onMatch(v);
      }
      for (final value in node.values) {
        _collectRenderers(value, keys, onMatch);
      }
    } else if (node is List) {
      for (final item in node) {
        _collectRenderers(item, keys, onMatch);
      }
    }
  }

  static Map<String, dynamic>? _findPlaylistRoot(dynamic node) {
    if (node is Map) {
      if (node['playlist'] is Map<String, dynamic>) {
        return node['playlist'] as Map<String, dynamic>;
      }
      if (node['playlistVideoListRenderer'] is Map<String, dynamic>) {
        return node['playlistVideoListRenderer'] as Map<String, dynamic>;
      }
      for (final v in node.values) {
        final r = _findPlaylistRoot(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final item in node) {
        final r = _findPlaylistRoot(item);
        if (r != null) return r;
      }
    }
    return null;
  }

  static String? _extractPlaylistTitle(Map<String, dynamic> initial) {
    final meta = initial['metadata'] as Map<String, dynamic>?;
    final plMeta = meta?['playlistMetadataRenderer'] as Map<String, dynamic>?;
    final t = (plMeta?['title'] as String?)?.trim();
    if (t != null && t.isNotEmpty) return t;
    return null;
  }

  static String? _findContinuation(dynamic node) {
    if (node is Map) {
      if (node['continuationCommand'] is Map<String, dynamic>) {
        final tok = node['continuationCommand']['token'] as String?;
        if (tok != null && tok.isNotEmpty) return tok;
      }
      for (final v in node.values) {
        final r = _findContinuation(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final item in node) {
        final r = _findContinuation(item);
        if (r != null) return r;
      }
    }
    return null;
  }

  /// 7/24 canlı yayınları veya henüz başlamamış yayınları ayırt eder.
  static bool isLiveRenderer(Map<String, dynamic> map) {
    if (map['upcomingEventData'] != null) return true;
    final badges = map['badges'];
    if (badges is List) {
      for (final b in badges.whereType<Map>()) {
        final mr = b['metadataBadgeRenderer'];
        if (mr is Map) {
          final style = (mr['style']?.toString() ?? '').toUpperCase();
          final label = (mr['label']?.toString() ?? '').toUpperCase();
          if (style.contains('LIVE') ||
              label == 'LIVE' ||
              label == 'CANLI' ||
              label.contains('LIVE NOW')) {
            return true;
          }
        }
      }
    }
    final overlays = map['thumbnailOverlays'];
    if (overlays is List) {
      for (final o in overlays.whereType<Map>()) {
        final ts = o['thumbnailOverlayTimeStatusRenderer'];
        if (ts is Map) {
          final style = (ts['style']?.toString() ?? '').toUpperCase();
          final txt = (_readText(ts['text']) ?? '').toUpperCase();
          if (style == 'LIVE' || txt == 'LIVE' || txt == 'CANLI') {
            return true;
          }
        }
      }
    }
    return false;
  }

  static PlaylistItem? _parseRenderer(
    Map<String, dynamic> map, {
    required int index,
  }) {
    final id = (map['videoId'] as String?)?.trim();
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      return null;
    }
    if (isLiveRenderer(map)) return null;
    final title = _readText(map['title']) ?? 'YouTube Parçası';
    final artist = _readText(map['ownerText']) ??
        _readText(map['shortBylineText']) ??
        _readText(map['longBylineText']) ??
        'YouTube';
    final lengthText =
        _readText(map['lengthText']) ?? _readText(map['lengthSeconds']);
    final duration = _parseDurationText(lengthText) ??
        double.tryParse('${map['lengthSeconds'] ?? ''}');
    return PlaylistItem(
      id: id,
      url: 'https://www.youtube.com/watch?v=$id',
      title: title,
      artist: artist,
      duration: duration,
      index: index,
    );
  }

  static String? _readText(dynamic obj) {
    if (obj is String && obj.trim().isNotEmpty) return obj.trim();
    if (obj is Map) {
      final simple = obj['simpleText'] as String?;
      if (simple != null && simple.trim().isNotEmpty) return simple.trim();
      final runs = obj['runs'] as List<dynamic>?;
      if (runs != null && runs.isNotEmpty) {
        final text = runs
            .map((r) => (r is Map ? r['text']?.toString() : '') ?? '')
            .join()
            .trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  static double? _parseDurationText(String? text) {
    if (text == null || text.isEmpty) return null;
    final parts = text.split(':').map((e) => int.tryParse(e.trim())).toList();
    if (parts.any((e) => e == null)) return null;
    if (parts.length == 2) return (parts[0]! * 60 + parts[1]!).toDouble();
    if (parts.length == 3) {
      return (parts[0]! * 3600 + parts[1]! * 60 + parts[2]!).toDouble();
    }
    return null;
  }
}

/// Ritim Android YouTube Akış Çözümleyici ve Dosya İndirici.
///
/// İki katmanlı koruma mimarisi:
/// 1) Normal uzunluktaki parça/kliplerde (`<= 9.2 MB`) `ANDROID` + `visitorData`
///    ile tekli `Range: bytes=0-(clen-1)` isteği üzerinden yüksek kaliteli
///    `itag=140` M4A ses ve `1080p/720p` H.264 MP4 video akışlarını indirir.
/// 2) 1 saatlik uzun setlerde veya YouTube SABR kısıtlaması olan videolarda
///    otomatik olarak sınırsız boyutlu `itag=18` birleşik MP4 akışına geçer
///    (ve ses modunda cihaz üzerinde kayıpsız M4A ses ayrıştırması uygular).
class NativeYouTubeDownloaderEngine {
  NativeYouTubeDownloaderEngine({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Tek bir `Range` isteği ile güvenli biçimde çekilebilen uyarlamalı akış üst sınırı (~9.2 MB).
  static const int kMaxAdaptiveSingleRangeBytes = 9200000;

  static const String _webWatchUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const _clients = <Map<String, dynamic>>[
    {
      'name': 'ANDROID',
      'userAgent':
          'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
      'clientId': '3',
      'clientVersion': '20.10.38',
      'context': {
        'client': {
          'clientName': 'ANDROID',
          'clientVersion': '20.10.38',
          'androidSdkVersion': 34,
          'osName': 'Android',
          'osVersion': '14',
          'hl': 'en',
          'gl': 'US',
        },
      },
    },
    {
      'name': 'IOS',
      'userAgent':
          'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X)',
      'clientId': '5',
      'clientVersion': '20.10.4',
      'context': {
        'client': {
          'clientName': 'IOS',
          'clientVersion': '20.10.4',
          'deviceMake': 'Apple',
          'deviceModel': 'iPhone16,2',
          'osName': 'iPhone',
          'osVersion': '18.3.2.22D82',
          'hl': 'en',
          'gl': 'US',
        },
      },
    },
    {
      'name': 'ANDROID_VR',
      'userAgent':
          'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      'clientId': '28',
      'clientVersion': '1.60.19',
      'context': {
        'client': {
          'clientName': 'ANDROID_VR',
          'clientVersion': '1.60.19',
          'deviceMake': 'Oculus',
          'deviceModel': 'Quest 3',
          'androidSdkVersion': 32,
          'osName': 'Android',
          'osVersion': '12L',
          'hl': 'en',
          'gl': 'US',
        },
      },
    },
  ];

  Future<String?> fetchVisitorData(String videoId) async {
    try {
      final resp = await _client.get(
        Uri.https('www.youtube.com', '/watch', {'v': videoId, 'hl': 'en'}),
        headers: {
          'User-Agent': _webWatchUa,
          'Accept-Language': 'en-US,en;q=0.9',
          'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
        },
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final match =
          RegExp(r'"VISITOR_DATA"\s*:\s*"([^"]+)"').firstMatch(html);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  Future<ResolvedYouTubeMedia> resolve(
    Uri canonicalUrl, {
    required DownloadFormat format,
    required DownloadQuality quality,
  }) async {
    final videoId = canonicalUrl.queryParameters['v'] ?? '';
    if (videoId.isEmpty) {
      final ext = canonicalUrl.path.contains('.')
          ? canonicalUrl.path.split('.').last.toLowerCase()
          : (format == DownloadFormat.mp4 ? 'mp4' : 'm4a');
      final direct = ResolvedMediaStream(
        url: canonicalUrl,
        headers: const {},
        fileExtension: ext,
        bitrate: 192000,
        includesAudio: true,
        requiresRange: false,
      );
      return ResolvedYouTubeMedia(
        title: canonicalUrl.pathSegments.isNotEmpty
            ? Uri.decodeComponent(canonicalUrl.pathSegments.last)
            : 'Medya',
        artist: canonicalUrl.host,
        audio: direct,
        muxedVideo: format == DownloadFormat.mp4 ? direct : null,
        video: format == DownloadFormat.mp4 ? direct : null,
        sourceAudioBitrate: 192000,
      );
    }

    final visitorData = await fetchVisitorData(videoId);
    String? lastReason;

    for (final profile in _clients) {
      try {
        final parsed = await _queryPlayerProfile(
          profile: profile,
          videoId: videoId,
          visitorData: visitorData,
          format: format,
          quality: quality,
        );
        if (parsed != null) return parsed;
      } on _FatalMediaException catch (fe) {
        throw RitimException(fe.message);
      } catch (e) {
        lastReason = e.toString().replaceFirst('RitimException: ', '');
      }
    }

    throw RitimException(
        'Bu video şu anda indirilemiyor. ${lastReason ?? 'YouTube koruma yanıtı verdi.'}');
  }

  /// HD video + ses birleştirme sırasında ikinci akış için taze `/player` oturumu açar.
  Future<ResolvedMediaStream?> resolveFreshAdaptiveAudio(
    String videoId,
    DownloadQuality quality,
  ) async {
    try {
      final visitorData = await fetchVisitorData(videoId);
      for (final profile in _clients.take(2)) {
        try {
          final media = await _queryPlayerProfile(
            profile: profile,
            videoId: videoId,
            visitorData: visitorData,
            format: DownloadFormat.mp3,
            quality: quality,
          );
          if (media?.adaptiveAudio != null) {
            return media!.adaptiveAudio;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  Future<void> downloadThumbnail(String videoId, File destination) async {
    if (videoId.isEmpty) return;
    await destination.parent.create(recursive: true);
    for (final variant in const ['hqdefault.jpg', 'mqdefault.jpg']) {
      try {
        final resp = await _client
            .get(Uri.parse('https://i.ytimg.com/vi/$videoId/$variant'))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode >= 200 &&
            resp.statusCode < 300 &&
            resp.bodyBytes.length > 1024) {
          await destination.writeAsBytes(resp.bodyBytes);
          return;
        }
      } catch (_) {}
    }
  }

  Future<ResolvedYouTubeMedia?> _queryPlayerProfile({
    required Map<String, dynamic> profile,
    required String videoId,
    required String? visitorData,
    required DownloadFormat format,
    required DownloadQuality quality,
  }) async {
    final ua = profile['userAgent'] as String;
    final baseContext = profile['context'] as Map<String, dynamic>;
    final clientCtx =
        Map<String, dynamic>.from(baseContext['client'] as Map<String, dynamic>);
    if (visitorData != null && visitorData.isNotEmpty) {
      clientCtx['visitorData'] = visitorData;
    }

    final reqHeaders = <String, String>{
      'User-Agent': ua,
      'Content-Type': 'application/json',
      'X-Youtube-Client-Name': profile['clientId'] as String,
      'X-Youtube-Client-Version': profile['clientVersion'] as String,
      if (visitorData != null && visitorData.isNotEmpty)
        'X-Goog-Visitor-Id': visitorData,
    };

    final resp = await _client
        .post(
          Uri.https('www.youtube.com', '/youtubei/v1/player',
              {'prettyPrint': 'false'}),
          headers: reqHeaders,
          body: jsonEncode({
            'videoId': videoId,
            'context': {'client': clientCtx},
            'contentCheckOk': true,
            'racyCheckOk': true,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw RitimException('HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
    if (data is! Map<String, dynamic>) return null;

    final playMap = data['playabilityStatus'] as Map?;
    final playStatus = playMap?['status'] as String?;
    if (playStatus != 'OK') {
      final reason = playMap?['reason']?.toString() ?? playStatus ?? 'Bilinmeyen durum';
      throw RitimException(reason);
    }

    final details = data['videoDetails'] as Map<String, dynamic>? ?? const {};
    final title = (details['title'] as String?)?.trim() ?? 'YouTube Parçası';
    final artist = (details['author'] as String?)?.trim() ?? 'YouTube';
    final durationSec =
        double.tryParse('${details['lengthSeconds'] ?? 0}') ?? 0;
    final isLive = details['isLive'] == true ||
        (details['isLiveContent'] == true && durationSec <= 0);
    if (isLive) {
      throw const _FatalMediaException(
        'Canlı yayınlar (7/24 radyo) dosya olarak indirilemez; normal bir şarkı veya video seç.',
      );
    }

    final streaming =
        data['streamingData'] as Map<String, dynamic>? ?? const {};
    final rawMuxed = (streaming['formats'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final rawAdaptive =
        (streaming['adaptiveFormats'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();

    if (streaming['hlsManifestUrl'] != null &&
        rawMuxed.isEmpty &&
        rawAdaptive.isEmpty) {
      throw const _FatalMediaException(
        'Canlı yayın akışları çevrimdışı dosya olarak kaydedilemez.',
      );
    }

    final streamHeaders = <String, String>{
      'User-Agent': ua,
      if (visitorData != null && visitorData.isNotEmpty)
        'X-Goog-Visitor-Id': visitorData,
    };

    final muxedVideos = <ResolvedMediaStream>[];
    final adaptiveAudios = <ResolvedMediaStream>[];
    final adaptiveVideos = <ResolvedMediaStream>[];
    var highestRes = 0;

    for (final f in rawMuxed) {
      final stream = _parseStreamMap(
        f,
        headers: streamHeaders,
        isAdaptive: false,
      );
      if (stream == null) continue;
      if ((stream.resolution ?? 0) > highestRes) {
        highestRes = stream.resolution!;
      }
      if (stream.fileExtension == 'mp4') {
        muxedVideos.add(stream);
      }
    }

    for (final f in rawAdaptive) {
      final stream = _parseStreamMap(
        f,
        headers: streamHeaders,
        isAdaptive: true,
      );
      if (stream == null) continue;
      if ((stream.resolution ?? 0) > highestRes) {
        highestRes = stream.resolution!;
      }
      if (stream.fileExtension == 'm4a') {
        adaptiveAudios.add(stream);
      } else if (stream.fileExtension == 'mp4') {
        adaptiveVideos.add(stream);
      }
    }

    if (muxedVideos.isEmpty && adaptiveAudios.isEmpty && adaptiveVideos.isEmpty) {
      throw RitimException('Uyumlu M4A/MP4 akışı bulunamadı (${profile['name']}).');
    }

    // Ses sıralaması: itag=140 (128kbps AAC-LC) öncelikli, ardından yüksek bitrate
    adaptiveAudios.sort((a, b) {
      final a140 = a.itag == 140 ? 1 : 0;
      final b140 = b.itag == 140 ? 1 : 0;
      if (a140 != b140) return b140.compareTo(a140);
      return b.bitrate.compareTo(a.bitrate);
    });

    muxedVideos.sort((a, b) {
      final ra = a.resolution ?? 0;
      final rb = b.resolution ?? 0;
      if (ra != rb) return rb.compareTo(ra);
      return b.bitrate.compareTo(a.bitrate);
    });

    final chosenMuxed = muxedVideos.isNotEmpty ? muxedVideos.first : null;
    final chosenAdaptiveAudio =
        adaptiveAudios.isNotEmpty ? adaptiveAudios.first : null;

    ResolvedMediaStream? chosenAdaptiveVideo;
    if (adaptiveVideos.isNotEmpty) {
      final maxRes = quality == DownloadQuality.highest ? 2160 : 1080;
      final withinLimit = adaptiveVideos
          .where((v) =>
              (v.resolution ?? 720) <= maxRes &&
              v.contentLength > 0 &&
              v.contentLength <= kMaxAdaptiveSingleRangeBytes)
          .toList()
        ..sort((a, b) {
          final ra = a.resolution ?? 0;
          final rb = b.resolution ?? 0;
          if (ra != rb) return rb.compareTo(ra);
          return b.bitrate.compareTo(a.bitrate);
        });
      if (withinLimit.isNotEmpty) {
        chosenAdaptiveVideo = withinLimit.first;
      } else {
        final fallbackCandidates = adaptiveVideos
            .where((v) => (v.resolution ?? 720) <= maxRes)
            .toList()
          ..sort((a, b) => (b.resolution ?? 0).compareTo(a.resolution ?? 0));
        chosenAdaptiveVideo = fallbackCandidates.isNotEmpty
            ? fallbackCandidates.first
            : adaptiveVideos.first;
      }
    }

    // Uzun videolarda (>9.2MB) birleşik MP4 (itag=18) yoksa diğer istemciyi dene
    final audioNeedsMuxFallback = chosenAdaptiveAudio == null ||
        chosenAdaptiveAudio.contentLength <= 0 ||
        chosenAdaptiveAudio.contentLength > kMaxAdaptiveSingleRangeBytes;
    if (audioNeedsMuxFallback && chosenMuxed == null) {
      throw RitimException(
          'Uzun medya için birleşik akış bulunamadı (${profile['name']}).');
    }

    final primaryAudio = chosenAdaptiveAudio ?? chosenMuxed!;
    final primaryVideo = format == DownloadFormat.mp4
        ? (chosenAdaptiveVideo != null &&
                chosenAdaptiveVideo.contentLength > 0 &&
                chosenAdaptiveVideo.contentLength <=
                    kMaxAdaptiveSingleRangeBytes &&
                chosenAdaptiveAudio != null &&
                chosenAdaptiveAudio.contentLength > 0 &&
                chosenAdaptiveAudio.contentLength <=
                    kMaxAdaptiveSingleRangeBytes
            ? chosenAdaptiveVideo
            : (chosenMuxed ?? chosenAdaptiveVideo))
        : null;

    return ResolvedYouTubeMedia(
      videoId: videoId,
      title: title,
      artist: artist,
      audio: primaryAudio,
      adaptiveAudio: chosenAdaptiveAudio,
      adaptiveVideo: chosenAdaptiveVideo,
      muxedVideo: chosenMuxed,
      video: primaryVideo,
      actualResolution:
          primaryVideo?.resolution ?? chosenMuxed?.resolution,
      sourceHighestResolution: highestRes > 0 ? highestRes : null,
      sourceAudioBitrate: primaryAudio.bitrate,
      durationSeconds: durationSec,
    );
  }

  static ResolvedMediaStream? _parseStreamMap(
    Map<String, dynamic> f, {
    required Map<String, String> headers,
    required bool isAdaptive,
  }) {
    final rawUrl = (f['url'] as String?)?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return null;

    final mime = (f['mimeType'] as String? ?? '').toLowerCase();
    final itag = (f['itag'] as num?)?.toInt();
    final bitrate = (f['bitrate'] as num?)?.toInt() ?? 128000;
    final height = (f['height'] as num?)?.toInt();
    final clen = int.tryParse('${f['contentLength'] ?? ''}') ??
        int.tryParse(uri.queryParameters['clen'] ?? '') ??
        0;

    if (mime.startsWith('audio/mp4') ||
        (mime.startsWith('audio/') && mime.contains('mp4a'))) {
      return ResolvedMediaStream(
        url: uri,
        headers: headers,
        fileExtension: 'm4a',
        bitrate: bitrate,
        contentLength: clen,
        itag: itag,
        includesAudio: true,
        requiresRange: isAdaptive,
      );
    }

    if (mime.startsWith('video/mp4') &&
        (mime.contains('avc1') || !isAdaptive)) {
      final hasAudio = !isAdaptive ||
          (f['audioQuality'] != null) ||
          mime.contains('mp4a');
      return ResolvedMediaStream(
        url: uri,
        headers: headers,
        fileExtension: 'mp4',
        bitrate: bitrate,
        contentLength: clen,
        itag: itag,
        resolution: height,
        includesAudio: hasAudio,
        requiresRange: isAdaptive,
      );
    }
    return null;
  }

  Future<void> downloadStream({
    required ResolvedMediaStream stream,
    required File destination,
    required bool Function() isCancelled,
    required void Function(int received, int expected, double bps) onProgress,
  }) async {
    if (stream.requiresRange &&
        (stream.contentLength <= 0 ||
            stream.contentLength > kMaxAdaptiveSingleRangeBytes)) {
      throw const RitimException(
          'Uyarlamalı akış boyutu sınırı aşıldı, birleşik akışa geçiliyor.');
    }

    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(stream.url);
      for (final entry in stream.headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (stream.requiresRange && stream.contentLength > 0) {
        request.headers.set('Range', 'bytes=0-${stream.contentLength - 1}');
      }

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RitimException(
            'İndirme akışı hata döndürdü (${response.statusCode}).');
      }

      final expected = response.contentLength > 0
          ? response.contentLength
          : stream.contentLength;
      await destination.parent.create(recursive: true);
      final sink = destination.openWrite();
      var received = 0;
      final sw = Stopwatch()..start();
      var lastEmitMs = 0;

      try {
        await for (final chunk in response) {
          if (isCancelled()) {
            throw const RitimException('İndirme iptal edildi.');
          }
          sink.add(chunk);
          received += chunk.length;
          final ms = sw.elapsedMilliseconds;
          if (ms - lastEmitMs >= 160 || (expected > 0 && received >= expected)) {
            lastEmitMs = ms;
            final sec = ms / 1000.0;
            final bps = sec > 0.1 ? received / sec : 0.0;
            onProgress(received, expected, bps);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (!destination.existsSync() || destination.lengthSync() < 1024) {
        throw const RitimException('İndirilen medya dosyası eksik veya boş.');
      }
      if (expected > 8192 && destination.lengthSync() < (expected * 0.95).floor()) {
        throw const RitimException('Medya aktarımı tamamlanmadan kesildi.');
      }
    } finally {
      client.close(force: true);
    }
  }
}
