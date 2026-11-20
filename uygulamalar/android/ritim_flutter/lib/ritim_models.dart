import 'package:flutter/material.dart';

enum MediaKind {
  audio,
  video;

  static MediaKind fromRaw(String? v) =>
      v == 'video' ? MediaKind.video : MediaKind.audio;
}

enum RepeatMode { off, all, one }

enum DownloadFormat {
  mp3,
  mp4;

  static DownloadFormat fromRaw(String? v) =>
      v == 'mp4' ? DownloadFormat.mp4 : DownloadFormat.mp3;
}

enum DownloadQuality {
  standard('Standart'),
  highest('En yüksek');

  const DownloadQuality(this.title);
  final String title;

  String detail(DownloadFormat format) {
    switch ((this, format)) {
      case (DownloadQuality.standard, DownloadFormat.mp3):
        return '192 kbps ses (M4A/MP3)';
      case (DownloadQuality.highest, DownloadFormat.mp3):
        return 'En yüksek kaliteli ses';
      case (DownloadQuality.standard, DownloadFormat.mp4):
        return 'Kaynakta varsa 1080p MP4';
      case (DownloadQuality.highest, DownloadFormat.mp4):
        return 'Cihaza uygun en yüksek video (4K’ya kadar)';
    }
  }

  static DownloadQuality fromRaw(String? v) =>
      v == 'highest' ? DownloadQuality.highest : DownloadQuality.standard;
}

enum DownloadStatus {
  queued('Sırada'),
  preparing('Hazırlanıyor'),
  downloading('İndiriliyor'),
  completed('Kütüphaneye eklendi'),
  failed('İndirilemedi'),
  cancelled('İptal edildi');

  const DownloadStatus(this.title);
  final String title;

  bool get isActive =>
      this == queued || this == preparing || this == downloading;

  static DownloadStatus fromRaw(String? v) =>
      DownloadStatus.values.firstWhere(
        (e) => e.name == v,
        orElse: () => DownloadStatus.queued,
      );
}

enum DownloadStage {
  resolving('Bağlantı hazırlanıyor'),
  transferring('Kaynak aktarılıyor'),
  converting('Medya hazırlanıyor'),
  saving('Kitaplığa kaydediliyor');

  const DownloadStage(this.title);
  final String title;

  static DownloadStage? fromRaw(String? v) {
    if (v == null) return null;
    for (final s in DownloadStage.values) {
      if (s.name == v) return s;
    }
    return null;
  }
}

class MediaTrack {
  MediaTrack({
    required this.id,
    required this.title,
    this.artist = 'Bilinmeyen sanatçı',
    this.kind = MediaKind.audio,
    required this.fileName,
    this.duration = 0,
    DateTime? addedAt,
    this.isFavorite = false,
    this.playCount = 0,
    this.lastPlayedAt,
    this.sourceURL,
    this.fileSize = 0,
    this.downloadQuality,
    this.downloadEntryID,
    this.album,
    this.artworkFileName,
    this.discNumber,
    this.trackNumber,
  }) : addedAt = addedAt ?? DateTime.now();

  final String id;
  String title;
  String artist;
  MediaKind kind;
  String fileName;
  double duration;
  DateTime addedAt;
  bool isFavorite;
  int playCount;
  DateTime? lastPlayedAt;
  String? sourceURL;
  int fileSize;
  DownloadQuality? downloadQuality;
  String? downloadEntryID;
  String? album;
  String? artworkFileName;
  int? discNumber;
  int? trackNumber;

  int get colorIndex => id.codeUnits.fold<int>(0, (a, b) => a + b) % 6;

  MediaTrack copyWith({
    String? title,
    String? artist,
    MediaKind? kind,
    String? fileName,
    double? duration,
    DateTime? addedAt,
    bool? isFavorite,
    int? playCount,
    DateTime? lastPlayedAt,
    String? sourceURL,
    int? fileSize,
    DownloadQuality? downloadQuality,
    String? downloadEntryID,
    String? album,
    String? artworkFileName,
    int? discNumber,
    int? trackNumber,
  }) {
    return MediaTrack(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      kind: kind ?? this.kind,
      fileName: fileName ?? this.fileName,
      duration: duration ?? this.duration,
      addedAt: addedAt ?? this.addedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      sourceURL: sourceURL ?? this.sourceURL,
      fileSize: fileSize ?? this.fileSize,
      downloadQuality: downloadQuality ?? this.downloadQuality,
      downloadEntryID: downloadEntryID ?? this.downloadEntryID,
      album: album ?? this.album,
      artworkFileName: artworkFileName ?? this.artworkFileName,
      discNumber: discNumber ?? this.discNumber,
      trackNumber: trackNumber ?? this.trackNumber,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'kind': kind.name,
        'fileName': fileName,
        'duration': duration,
        'addedAt': addedAt.toIso8601String(),
        'isFavorite': isFavorite,
        'playCount': playCount,
        if (lastPlayedAt != null) 'lastPlayedAt': lastPlayedAt!.toIso8601String(),
        if (sourceURL != null) 'sourceURL': sourceURL,
        'fileSize': fileSize,
        if (downloadQuality != null) 'downloadQuality': downloadQuality!.name,
        if (downloadEntryID != null) 'downloadEntryID': downloadEntryID,
        if (album != null) 'album': album,
        if (artworkFileName != null) 'artworkFileName': artworkFileName,
        if (discNumber != null) 'discNumber': discNumber,
        if (trackNumber != null) 'trackNumber': trackNumber,
      };

  factory MediaTrack.fromJson(Map<String, dynamic> json) {
    return MediaTrack(
      id: (json['id'] ?? '') as String,
      title: (json['title'] ?? 'İsimsiz parça') as String,
      artist: (json['artist'] ?? 'Bilinmeyen sanatçı') as String,
      kind: MediaKind.fromRaw(json['kind'] as String?),
      fileName: (json['fileName'] ?? '') as String,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      addedAt: DateTime.tryParse((json['addedAt'] ?? '') as String) ?? DateTime.now(),
      isFavorite: json['isFavorite'] == true,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      lastPlayedAt: json['lastPlayedAt'] != null
          ? DateTime.tryParse(json['lastPlayedAt'] as String)
          : null,
      sourceURL: json['sourceURL'] as String?,
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      downloadQuality: json['downloadQuality'] != null
          ? DownloadQuality.fromRaw(json['downloadQuality'] as String?)
          : null,
      downloadEntryID: json['downloadEntryID'] as String?,
      album: json['album'] as String?,
      artworkFileName: json['artworkFileName'] as String?,
      discNumber: (json['discNumber'] as num?)?.toInt(),
      trackNumber: (json['trackNumber'] as num?)?.toInt(),
    );
  }
}

class MediaPlaylist {
  MediaPlaylist({
    required this.id,
    required this.name,
    List<String>? trackIDs,
    DateTime? createdAt,
    this.isPinned = false,
    this.detail,
    this.coverTrackID,
  })  : trackIDs = trackIDs ?? <String>[],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  List<String> trackIDs;
  DateTime createdAt;
  bool isPinned;
  String? detail;
  String? coverTrackID;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIDs': trackIDs,
        'createdAt': createdAt.toIso8601String(),
        'isPinned': isPinned,
        if (detail != null) 'detail': detail,
        if (coverTrackID != null) 'coverTrackID': coverTrackID,
      };

  factory MediaPlaylist.fromJson(Map<String, dynamic> json) {
    return MediaPlaylist(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? 'Liste') as String,
      trackIDs: (json['trackIDs'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '') as String) ?? DateTime.now(),
      isPinned: json['isPinned'] == true,
      detail: json['detail'] as String?,
      coverTrackID: json['coverTrackID'] as String?,
    );
  }
}

class DownloadEntry {
  DownloadEntry({
    required this.id,
    required this.title,
    required this.sourceURL,
    this.format = DownloadFormat.mp3,
    this.quality = DownloadQuality.standard,
    this.progress = 0,
    this.status = DownloadStatus.queued,
    this.error,
    this.trackID,
    this.artist,
    this.batchID,
    this.batchName,
    this.playlistID,
    this.additionalPlaylistIDs = const [],
    this.resolvedQuality,
    this.qualityNote,
    this.priority = 0,
    this.stage,
    this.retryCount = 0,
    this.receivedBytes,
    this.expectedBytes,
    this.bytesPerSecond,
  });

  final String id;
  String title;
  String sourceURL;
  DownloadFormat format;
  DownloadQuality quality;
  double progress;
  DownloadStatus status;
  String? error;
  String? trackID;
  String? artist;
  String? batchID;
  String? batchName;
  String? playlistID;
  List<String> additionalPlaylistIDs;
  String? resolvedQuality;
  String? qualityNote;
  int priority;
  DownloadStage? stage;
  int retryCount;
  int? receivedBytes;
  int? expectedBytes;
  double? bytesPerSecond;

  bool get isActive => status.isActive;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourceURL': sourceURL,
        'format': format.name,
        'quality': quality.name,
        'progress': progress,
        'status': status.name,
        if (error != null) 'error': error,
        if (trackID != null) 'trackID': trackID,
        if (artist != null) 'artist': artist,
        if (batchID != null) 'batchID': batchID,
        if (batchName != null) 'batchName': batchName,
        if (playlistID != null) 'playlistID': playlistID,
        if (additionalPlaylistIDs.isNotEmpty)
          'additionalPlaylistIDs': additionalPlaylistIDs,
        if (resolvedQuality != null) 'resolvedQuality': resolvedQuality,
        if (qualityNote != null) 'qualityNote': qualityNote,
        'priority': priority,
        if (stage != null) 'stage': stage!.name,
        'retryCount': retryCount,
        if (receivedBytes != null) 'receivedBytes': receivedBytes,
        if (expectedBytes != null) 'expectedBytes': expectedBytes,
        if (bytesPerSecond != null) 'bytesPerSecond': bytesPerSecond,
      };

  factory DownloadEntry.fromJson(Map<String, dynamic> json) {
    return DownloadEntry(
      id: (json['id'] ?? '') as String,
      title: (json['title'] ?? 'İndiriliyor') as String,
      sourceURL: (json['sourceURL'] ?? '') as String,
      format: DownloadFormat.fromRaw(json['format'] as String?),
      quality: DownloadQuality.fromRaw(json['quality'] as String?),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      status: DownloadStatus.fromRaw(json['status'] as String?),
      error: json['error'] as String?,
      trackID: json['trackID'] as String?,
      artist: json['artist'] as String?,
      batchID: json['batchID'] as String?,
      batchName: json['batchName'] as String?,
      playlistID: json['playlistID'] as String?,
      additionalPlaylistIDs:
          (json['additionalPlaylistIDs'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(),
      resolvedQuality: json['resolvedQuality'] as String?,
      qualityNote: json['qualityNote'] as String?,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      stage: DownloadStage.fromRaw(json['stage'] as String?),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      receivedBytes: (json['receivedBytes'] as num?)?.toInt(),
      expectedBytes: (json['expectedBytes'] as num?)?.toInt(),
      bytesPerSecond: (json['bytesPerSecond'] as num?)?.toDouble(),
    );
  }
}

class PlaylistItem {
  const PlaylistItem({
    required this.id,
    required this.url,
    required this.title,
    required this.artist,
    this.duration,
    required this.index,
  });

  final String id;
  final String url;
  final String title;
  final String artist;
  final double? duration;
  final int index;

  String get thumbnailUrl => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
}

class PlaylistPreview {
  const PlaylistPreview({
    required this.id,
    required this.title,
    required this.items,
    this.skipped = 0,
    this.truncated = false,
    this.error,
  });

  final String id;
  final String title;
  final List<PlaylistItem> items;
  final int skipped;
  final bool truncated;
  final String? error;
}

class ListeningDay {
  ListeningDay({
    required this.dayKey,
    this.seconds = 0,
    Map<String, double>? trackSeconds,
  }) : trackSeconds = trackSeconds ?? <String, double>{};

  final String dayKey; // YYYY-MM-DD
  double seconds;
  final Map<String, double> trackSeconds;

  DateTime get date => DateTime.tryParse(dayKey) ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'dayKey': dayKey,
        'seconds': seconds,
        'trackSeconds': trackSeconds,
      };

  factory ListeningDay.fromJson(Map<String, dynamic> json) {
    final raw = json['trackSeconds'] as Map<String, dynamic>? ?? const {};
    return ListeningDay(
      dayKey: (json['dayKey'] ?? '') as String,
      seconds: (json['seconds'] as num?)?.toDouble() ?? 0,
      trackSeconds: raw.map(
        (k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0),
      ),
    );
  }
}

/// Akıllı Koleksiyonlar (Ritim SmartCollections eşleniği).
enum SmartCollection {
  unheard('Henüz dinlemediklerin', 'Kütüphanende olup henüz çalmadığın müzikler.', Icons.auto_awesome_rounded),
  recent('Yeni eklenenler', 'Son 30 günde eklediğin müzikler.', Icons.add_circle_outline_rounded),
  rediscover('Yeniden keşfet', 'En az 14 gündür dinlemediğin beğeniler.', Icons.favorite_rounded),
  history('Son dinlenenler', 'Her parçanın son çalınma zamanına göre müziklerin.', Icons.history_rounded);

  const SmartCollection(this.title, this.detail, this.icon);
  final String title;
  final String detail;
  final IconData icon;

  List<MediaTrack> tracksIn(List<MediaTrack> library, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final audio = library.where((t) => t.kind == MediaKind.audio);
    late final List<MediaTrack> filtered;
    switch (this) {
      case SmartCollection.unheard:
        filtered = audio.where((t) => t.playCount == 0).toList();
      case SmartCollection.recent:
        final cutoff = ref.subtract(const Duration(days: 30));
        filtered = audio
            .where((t) => !t.addedAt.isBefore(cutoff) && !t.addedAt.isAfter(ref))
            .toList();
      case SmartCollection.rediscover:
        final cutoff = ref.subtract(const Duration(days: 14));
        filtered = audio
            .where((t) =>
                t.isFavorite &&
                (t.lastPlayedAt == null || !t.lastPlayedAt!.isAfter(cutoff)))
            .toList();
      case SmartCollection.history:
        filtered = audio.where((t) => t.lastPlayedAt != null).toList();
    }

    filtered.sort((a, b) {
      final DateTime left;
      final DateTime right;
      if (this == SmartCollection.history) {
        left = a.lastPlayedAt!;
        right = b.lastPlayedAt!;
        return right.compareTo(left);
      } else if (this == SmartCollection.rediscover) {
        left = a.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        right = b.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = left.compareTo(right);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      } else {
        final cmp = b.addedAt.compareTo(a.addedAt);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      }
    });
    return filtered;
  }
}

class RitimException implements Exception {
  const RitimException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Ritim MediaURLPolicy (YouTube tekil video, playlist ve medya dosya doğrulaması).
class MediaURLPolicy {
  static const Set<String> mediaExtensions = {
    'mp3',
    'mp4',
    'm4a',
    'mov',
    'wav',
    'aiff',
    'aif',
    'aac',
    'caf',
    'webm',
    'ogg',
  };

  static const Set<String> youtubeHosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtu.be',
    'www.youtu.be',
  };

  static bool isYouTube(Uri uri) =>
      youtubeHosts.contains(uri.host.toLowerCase());

  static Uri validatedInput(String raw) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const RitimException(
          'Geçerli bir HTTPS YouTube veya medya bağlantısı gir.');
    }
    final ext = uri.path.contains('.')
        ? uri.path.split('.').last.toLowerCase()
        : '';
    if (!isYouTube(uri) && !mediaExtensions.contains(ext)) {
      throw const RitimException(
          'YouTube bağlantısı veya MP3, MP4, M4A, WAV gibi doğrudan bir medya dosyası kullan.');
    }
    return uri;
  }

  static bool isPlaylist(Uri uri) {
    if (!isYouTube(uri)) return false;
    final list = uri.queryParameters['list'];
    return list != null && list.isNotEmpty;
  }

  static Uri canonicalInput(String raw, {bool stripMix = false}) {
    var uri = validatedInput(raw);
    if (!isYouTube(uri)) return uri;
    if (stripMix && isPlaylist(uri) && uri.path == '/watch') {
      final qp = Map<String, String>.from(uri.queryParameters)
        ..remove('list')
        ..remove('index')
        ..remove('start_radio');
      uri = uri.replace(queryParameters: qp);
    } else if (isPlaylist(uri)) {
      throw const RitimException(
          'Oynatma listesi bağlantısını Oynatma listesi bölümünde çözümleyip parçaları seç.');
    }

    final parts = uri.pathSegments;
    String? id;
    if (uri.host.toLowerCase().endsWith('youtu.be')) {
      id = parts.isNotEmpty ? parts.first : null;
    } else if (parts.isNotEmpty && parts.first == 'watch') {
      id = uri.queryParameters['v'];
    } else if (parts.length == 2 &&
        const ['shorts', 'embed', 'live'].contains(parts.first)) {
      id = parts[1];
    }

    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      throw const RitimException(
          'Tek bir YouTube video bağlantısı gir; kanal bağlantıları eklenemez.');
    }
    return Uri.parse('https://www.youtube.com/watch?v=$id');
  }

  static Uri validatedPlaylist(String raw) {
    final uri = validatedInput(raw);
    final list = uri.queryParameters['list'];
    if (!isPlaylist(uri) ||
        !const ['/playlist', '/watch'].contains(uri.path) ||
        list == null ||
        !RegExp(r'^[A-Za-z0-9_-]{10,200}$').hasMatch(list)) {
      throw const RitimException(
          'Geçerli bir YouTube oynatma listesi bağlantısı gir.');
    }
    return Uri.parse('https://www.youtube.com/playlist?list=$list');
  }

  static String? downloadKey(
    String raw, {
    required DownloadFormat format,
    DownloadQuality? quality,
  }) {
    try {
      final canonical = canonicalInput(raw, stripMix: true);
      final key = '${canonical.toString()}|${format.name}';
      return isYouTube(canonical)
          ? '$key|${(quality ?? DownloadQuality.standard).name}'
          : key;
    } catch (_) {
      return null;
    }
  }
}
