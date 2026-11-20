import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'ritim_models.dart';

class LyricLine {
  const LyricLine({
    required this.id,
    required this.time,
    required this.text,
  });

  final int id;
  final double time;
  final String text;

  Map<String, dynamic> toJson() => {'id': id, 'time': time, 'text': text};

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
        id: (json['id'] as num?)?.toInt() ?? 0,
        time: (json['time'] as num?)?.toDouble() ?? 0,
        text: (json['text'] ?? '') as String,
      );
}

class TrackLyrics {
  TrackLyrics({
    required this.trackID,
    required this.rawText,
    required this.plainText,
    required this.lines,
    required this.sourceName,
    this.sourceURL,
    this.offset = 0,
    DateTime? savedAt,
    this.isInstrumental = false,
    this.hasUserEdits = false,
  }) : savedAt = savedAt ?? DateTime.now();

  final String trackID;
  String rawText;
  String plainText;
  List<LyricLine> lines;
  String sourceName;
  String? sourceURL;
  double offset;
  DateTime savedAt;
  bool isInstrumental;
  bool hasUserEdits;

  LyricLine? activeLine(double elapsed) {
    if (!elapsed.isFinite || lines.isEmpty) return null;
    final position = elapsed - offset;
    var low = 0;
    var high = lines.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].time <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low > 0 ? lines[low - 1] : null;
  }

  Map<String, dynamic> toJson() => {
        'trackID': trackID,
        'rawText': rawText,
        'plainText': plainText,
        'lines': lines.map((l) => l.toJson()).toList(),
        'sourceName': sourceName,
        if (sourceURL != null) 'sourceURL': sourceURL,
        'offset': offset,
        'savedAt': savedAt.toIso8601String(),
        'isInstrumental': isInstrumental,
        'hasUserEdits': hasUserEdits,
      };

  factory TrackLyrics.fromJson(Map<String, dynamic> json) => TrackLyrics(
        trackID: (json['trackID'] ?? '') as String,
        rawText: (json['rawText'] ?? '') as String,
        plainText: (json['plainText'] ?? '') as String,
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LyricLine.fromJson)
            .toList(),
        sourceName: (json['sourceName'] ?? 'Kayıtlı') as String,
        sourceURL: json['sourceURL'] as String?,
        offset: (json['offset'] as num?)?.toDouble() ?? 0,
        savedAt: DateTime.tryParse((json['savedAt'] ?? '') as String) ??
            DateTime.now(),
        isInstrumental: json['isInstrumental'] == true,
        hasUserEdits: json['hasUserEdits'] == true,
      );
}

class LyricsCandidate {
  const LyricsCandidate({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.hasSynced,
    required this.isInstrumental,
    this.plainLyrics,
    this.syncedLyrics,
  });

  final int id;
  final String title;
  final String artist;
  final String album;
  final double duration;
  final bool hasSynced;
  final bool isInstrumental;
  final String? plainLyrics;
  final String? syncedLyrics;
}

class LRCParser {
  static const int maxTextBytes = 512 * 1024;
  static final RegExp _timestamps =
      RegExp(r'\[(\d{1,4}):([0-5]\d)(?:[.:](\d{1,3}))?\]');
  static final RegExp _metadata =
      RegExp(r'^\[(ar|ti|al|by|re|ve|length|offset):.*\]$', caseSensitive: false);
  static final RegExp _offsetTag =
      RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]$', caseSensitive: false);

  static ({String plainText, List<LyricLine> lines}) parse(String raw) {
    if (utf8.encode(raw).length > maxTextBytes) {
      throw const RitimException(
          'Şarkı sözü dosyası fazla büyük. En fazla 512 KB metin kullan.');
    }
    final text = raw
        .replaceAll('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final plain = <String>[];
    final timed = <(double, String, int)>[];
    var offset = 0.0;

    for (final rawRow in text.split('\n')) {
      final row = rawRow.trim();
      final offMatch = _offsetTag.firstMatch(row);
      if (offMatch != null) {
        final ms = double.tryParse(offMatch.group(1) ?? '');
        if (ms != null && ms.isFinite) {
          offset = (ms / 1000.0).clamp(-86400.0, 86400.0);
          continue;
        }
      }
      if (_metadata.hasMatch(row)) continue;

      final matches = _timestamps.allMatches(row).toList();
      final times = <double>[];
      var end = 0;
      for (final match in matches) {
        if (row.substring(end, match.start).trim().isNotEmpty) break;
        final minutes = double.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = double.tryParse(match.group(2) ?? '0') ?? 0;
        final fracStr = match.group(3);
        final fraction =
            fracStr == null ? 0.0 : (double.tryParse('0.$fracStr') ?? 0.0);
        times.add(minutes * 60 + seconds + fraction);
        end = match.end;
      }
      final content = row.substring(end).trim();
      plain.add(content);
      for (final t in times) {
        if (timed.length >= 10000) {
          throw const RitimException('Şarkı sözü satır sınırı aşıldı.');
        }
        timed.add((t, content, timed.length));
      }
    }

    final adjusted = timed
        .map((r) => ((r.$1 - offset).clamp(0.0, double.infinity), r.$2, r.$3))
        .toList()
      ..sort((a, b) {
        final cmp = a.$1.compareTo(b.$1);
        return cmp != 0 ? cmp : a.$3.compareTo(b.$3);
      });

    return (
      plainText: plain.join('\n').trim(),
      lines: [
        for (var i = 0; i < adjusted.length; i++)
          LyricLine(id: i, time: adjusted[i].$1, text: adjusted[i].$2),
      ],
    );
  }
}

class LyricsService {
  LyricsService({required Directory directory, http.Client? client})
      : _file = File('${directory.path}/lyrics.json'),
        _client = client ?? http.Client();

  final File _file;
  final http.Client _client;
  final Map<String, TrackLyrics> _items = {};

  Map<String, TrackLyrics> get items => Map.unmodifiable(_items);

  Future<void> load() async {
    try {
      if (!_file.existsSync()) return;
      final raw = await _file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      for (final row in list) {
        if (row is Map<String, dynamic>) {
          final l = TrackLyrics.fromJson(row);
          if (l.trackID.isNotEmpty) _items[l.trackID] = l;
        }
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      await _file.parent.create(recursive: true);
      final encoded = jsonEncode(_items.values.take(200).map((e) => e.toJson()).toList());
      await _file.writeAsString(encoded);
    } catch (_) {}
  }

  TrackLyrics? lyricsFor(String trackID) => _items[trackID];

  Future<TrackLyrics> saveCustom(
    MediaTrack track, {
    required String rawText,
    String sourceName = 'Elle eklendi',
    String? sourceURL,
    bool hasUserEdits = true,
  }) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      throw const RitimException(
          'Kaydetmek için şarkı sözü veya zamanlı LRC satırı ekle.');
    }
    final parsed = LRCParser.parse(trimmed);
    if (parsed.plainText.isEmpty && parsed.lines.isEmpty) {
      throw const RitimException('Geçerli şarkı sözü metni bulunamadı.');
    }
    final existing = _items[track.id];
    final doc = TrackLyrics(
      trackID: track.id,
      rawText: trimmed,
      plainText: parsed.plainText,
      lines: parsed.lines,
      sourceName: sourceName,
      sourceURL: sourceURL,
      offset: existing?.offset ?? 0,
      hasUserEdits: hasUserEdits,
    );
    _items[track.id] = doc;
    await _persist();
    return doc;
  }

  Future<void> setOffset(String trackID, double offset) async {
    final doc = _items[trackID];
    if (doc == null) return;
    doc.offset = offset.clamp(-30.0, 30.0);
    await _persist();
  }

  Future<void> remove(String trackID) async {
    _items.remove(trackID);
    await _persist();
  }

  Future<TrackLyrics> fetchBestForTrack(MediaTrack track) async {
    final cleanTitle = _cleanTitle(track.title);
    final cleanArtist = _cleanArtist(track.artist);

    // 1. Önce doğrudan /api/get dene
    final params = <String, String>{
      'track_name': cleanTitle,
      if (cleanArtist.isNotEmpty) 'artist_name': cleanArtist,
      if (track.album != null && track.album!.trim().isNotEmpty)
        'album_name': track.album!.trim(),
      if (track.duration >= 5) 'duration': '${track.duration.round()}',
    };
    try {
      final resp = await _client
          .get(
            Uri.https('lrclib.net', '/api/get', params),
            headers: {'User-Agent': 'RitimAndroid/1.10.0'},
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final obj = jsonDecode(utf8.decode(resp.bodyBytes));
        if (obj is Map<String, dynamic>) {
          final cand = _fromJson(obj);
          if (cand != null) {
            return await applyCandidate(track, cand);
          }
        }
      }
    } catch (_) {}

    // 2. Olmazsa arama yap ve en iyi adayı seç
    final results = await searchLRCLIB('$cleanArtist $cleanTitle'.trim());
    if (results.isEmpty) {
      throw const RitimException(
          'Bu parça için LRCLIB üzerinde şarkı sözü bulunamadı. Sözleri elle ekleyebilirsin.');
    }
    results.sort((a, b) {
      if (a.hasSynced != b.hasSynced) return a.hasSynced ? -1 : 1;
      if (track.duration > 0) {
        return (a.duration - track.duration)
            .abs()
            .compareTo((b.duration - track.duration).abs());
      }
      return 0;
    });
    return await applyCandidate(track, results.first);
  }

  Future<List<LyricsCandidate>> searchLRCLIB(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    final resp = await _client
        .get(
          Uri.https('lrclib.net', '/api/search', {'q': clean}),
          headers: {'User-Agent': 'RitimAndroid/1.10.0'},
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 429) {
      throw const RitimException(
          'Şarkı sözü servisi meşgul. Birkaç saniye sonra yeniden dene.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw RitimException('LRCLIB yanıt vermedi (${resp.statusCode}).');
    }
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(_fromJson)
        .whereType<LyricsCandidate>()
        .toList();
  }

  Future<TrackLyrics> applyCandidate(
    MediaTrack track,
    LyricsCandidate candidate,
  ) async {
    if (candidate.isInstrumental &&
        (candidate.syncedLyrics ?? '').isEmpty &&
        (candidate.plainLyrics ?? '').isEmpty) {
      final doc = TrackLyrics(
        trackID: track.id,
        rawText: '',
        plainText: 'Enstrümantal parça',
        lines: const [],
        sourceName: 'LRCLIB',
        sourceURL: 'https://lrclib.net',
        isInstrumental: true,
      );
      _items[track.id] = doc;
      await _persist();
      return doc;
    }

    final raw = (candidate.syncedLyrics?.trim().isNotEmpty == true)
        ? candidate.syncedLyrics!
        : (candidate.plainLyrics ?? '');
    if (raw.trim().isEmpty) {
      throw const RitimException('Seçilen sonuçta şarkı sözü metni yok.');
    }
    final parsed = LRCParser.parse(raw);
    final doc = TrackLyrics(
      trackID: track.id,
      rawText: raw,
      plainText: parsed.plainText,
      lines: parsed.lines,
      sourceName: 'LRCLIB',
      sourceURL: 'https://lrclib.net',
      isInstrumental: candidate.isInstrumental,
    );
    _items[track.id] = doc;
    await _persist();
    return doc;
  }

  static LyricsCandidate? _fromJson(Map<String, dynamic> obj) {
    final id = (obj['id'] as num?)?.toInt();
    final title = (obj['trackName'] as String?)?.trim() ?? '';
    if (id == null || title.isEmpty) return null;
    final synced = obj['syncedLyrics'] as String?;
    final plain = obj['plainLyrics'] as String?;
    return LyricsCandidate(
      id: id,
      title: title,
      artist: (obj['artistName'] as String?)?.trim() ?? 'Bilinmeyen sanatçı',
      album: (obj['albumName'] as String?)?.trim() ?? '',
      duration: (obj['duration'] as num?)?.toDouble() ?? 0,
      hasSynced: synced != null && synced.trim().isNotEmpty,
      isInstrumental: obj['instrumental'] == true,
      plainLyrics: plain,
      syncedLyrics: synced,
    );
  }

  static String _cleanTitle(String raw) {
    return raw
        .replaceAll(
          RegExp(
            r'\s*[\(\[]\s*(official\s+(music\s+)?(video|audio|lyric(s)?(\s+video)?)|lyrics?|audio|hd|4k|visualizer)\s*[\)\]]',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  static String _cleanArtist(String raw) {
    if (raw == 'Bilinmeyen sanatçı' || raw == 'Ritim') return '';
    return raw.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').trim();
  }
}
