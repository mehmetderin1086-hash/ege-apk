import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'lyrics_service.dart';
import 'ritim_ai_service.dart';
import 'ritim_models.dart';
import 'theme_design.dart';
import 'youtube_engine.dart';

const MethodChannel _ritimChannel = MethodChannel('com.mehmetderin.ritim/platform');

class ArtistGroup {
  const ArtistGroup({
    required this.name,
    required this.tracks,
    this.artworkPath,
  });

  final String name;
  final List<MediaTrack> tracks;
  final String? artworkPath;
}

class AlbumGroup {
  const AlbumGroup({
    required this.title,
    required this.artist,
    required this.tracks,
    this.artworkPath,
  });

  final String title;
  final String artist;
  final List<MediaTrack> tracks;
  final String? artworkPath;
}

class RitimController extends ChangeNotifier {
  RitimController({
    this.overrideDirectory,
    this.enableNativePlayer = true,
  });

  final Directory? overrideDirectory;
  final bool enableNativePlayer;
  static const Uuid _uuid = Uuid();

  late Directory _rootDir;
  late Directory _libraryDir;
  late Directory _artworkDir;
  late Directory _tempDir;
  late File _stateFile;
  late File _downloadsFile;
  late File _listeningFile;
  late File _aiFile;

  bool initialized = false;
  RitimThemeStyle themeStyle = RitimThemeStyle.nane;
  RitimWallpaper wallpaper = RitimWallpaper.studio;
  RitimPalette get palette => RitimPalette.of(themeStyle);

  // Kütüphane
  final List<MediaTrack> tracks = [];
  final List<MediaPlaylist> playlists = [];
  bool isScanningMetadata = false;
  String? statusBanner;

  // Oynatıcı
  VideoPlayerController? videoController;
  MediaTrack? currentTrack;
  final List<MediaTrack> queue = [];
  final List<String> _shuffleRemaining = [];
  final List<String> _shuffleHistory = [];
  bool isPlaying = false;
  bool isLoadingMedia = false;
  double elapsed = 0;
  double duration = 0;
  double playbackRate = 1.0;
  bool shuffleEnabled = false;
  RepeatMode repeatMode = RepeatMode.off;
  int sleepMinutes = 0;
  DateTime? sleepDeadline;
  Timer? _heartbeatTimer;
  DateTime? _lastTickAt;
  double _lastSavedPosAt = 0;
  bool _isHandlingCompletion = false;

  // Dinleme İstatistikleri (366 gün)
  final Map<String, ListeningDay> _listeningByDay = {};

  // İndirme
  final NativeYouTubeCatalog catalog = NativeYouTubeCatalog();
  final NativeYouTubeDownloaderEngine downloader = NativeYouTubeDownloaderEngine();
  final List<DownloadEntry> downloadEntries = [];
  final Set<String> _cancelledIds = {};
  final Set<String> _activeWorkerIds = {};
  bool _healedV111 = false;
  int maxConcurrency = 4;
  DownloadFormat defaultFormat = DownloadFormat.mp3;
  DownloadQuality defaultQuality = DownloadQuality.standard;
  PlaylistPreview? playlistPreview;
  bool isLoadingPlaylist = false;

  // YouTube Keşif / Ara
  List<PlaylistItem> searchResults = [];
  bool isSearchingYouTube = false;
  String lastSearchQuery = '';
  String? searchError;

  // Şarkı Sözleri
  late LyricsService lyrics;
  bool isFetchingLyrics = false;
  List<LyricsCandidate> lyricsCandidates = [];
  String? lyricsError;

  // Yapay Zekâ Asistanı & CLIProxyAPI
  final RitimAIClient aiClient = RitimAIClient();
  AIConnectionConfig aiConfig = AIConnectionConfig();
  List<RitimAIModel> aiModels = [];
  final List<AIMessage> aiMessages = [];
  final Map<String, AITrackInsight> aiInsights = {};
  AIDailyMix? dailyMix;
  AIDJSession? djSession;
  final Set<String> excludedAiTrackIds = {};
  bool isLoadingModels = false;
  bool isSendingAi = false;
  bool isDailyLoading = false;
  bool isDjLoading = false;
  bool isInsightLoading = false;
  String? aiError;

  Future<void> init() async {
    if (initialized) return;
    _rootDir = overrideDirectory ?? await getApplicationDocumentsDirectory();
    _libraryDir = Directory('${_rootDir.path}/ritim_library');
    _artworkDir = Directory('${_rootDir.path}/ritim_artworks');
    _tempDir = Directory('${_rootDir.path}/ritim_tmp');
    await _libraryDir.create(recursive: true);
    await _artworkDir.create(recursive: true);
    await _tempDir.create(recursive: true);

    _stateFile = File('${_rootDir.path}/ritim_state.json');
    _downloadsFile = File('${_rootDir.path}/ritim_downloads.json');
    _listeningFile = File('${_rootDir.path}/ritim_listening.json');
    _aiFile = File('${_rootDir.path}/ritim_ai.json');

    lyrics = LyricsService(directory: _rootDir);
    await lyrics.load();
    await _loadState();
    await _loadDownloads();
    await _healLegacyDownloadsAndStubs();
    await _loadListening();
    await _loadAiState();

    if (tracks.isEmpty && overrideDirectory == null) {
      await _seedStarterTracks();
    }

    _restorePlaybackSession();
    if (enableNativePlayer) {
      _ritimChannel.setMethodCallHandler(_handlePlatformCall);
      _startHeartbeat();
      _pumpDownloads();
    }
    initialized = true;
    notifyListeners();
  }

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    if (call.method == 'onMediaAction') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final action = args?['action']?.toString() ?? '';
      switch (action) {
        case 'play':
          await play();
        case 'pause':
          await pause();
        case 'toggle':
          await togglePlayPause();
        case 'next':
          await nextTrack();
        case 'prev':
          await previousTrack();
        case 'seek':
          final posMs = (args?['positionMs'] as num?)?.toDouble() ?? 0;
          await seekTo(posMs / 1000.0);
      }
    }
    return null;
  }

  Future<void> _seedStarterTracks() async {
    final samples = [
      ('assets/audio/gece-yolu.m4a', 'gece-yolu.m4a', 'Gece Yolu', 'Ritim Studio', 'Gece Akustiği'),
      ('assets/audio/kiyi.m4a', 'kiyi.m4a', 'Kıyı', 'Ritim Studio', 'Sahil Sesleri'),
      ('assets/audio/yorunge.m4a', 'yorunge.m4a', 'Yörünge', 'Ritim Studio', 'Uzay & Ritm'),
    ];
    for (final s in samples) {
      try {
        final data = await rootBundle.load(s.$1);
        final id = _uuid.v4();
        final fileName = '$id.m4a';
        final out = File('${_libraryDir.path}/$fileName');
        await out.writeAsBytes(data.buffer.asUint8List());
        var dur = 42.0;
        var artist = s.$4;
        var title = s.$3;
        var album = s.$5;
        String? artName;
        if (enableNativePlayer) {
          try {
            final info = await _inspectFile(out.path);
            final d = (info['durationSeconds'] as num?)?.toDouble() ?? 0;
            if (d > 1) dur = d;
            final t = (info['title'] as String?)?.trim();
            if (t != null && t.isNotEmpty) title = t;
            final a = (info['artist'] as String?)?.trim();
            if (a != null && a.isNotEmpty) artist = a;
            final al = (info['album'] as String?)?.trim();
            if (al != null && al.isNotEmpty) album = al;
            artName = info['artworkPath'] as String?;
          } catch (_) {}
        }
        tracks.add(MediaTrack(
          id: id,
          title: title,
          artist: artist,
          album: album,
          kind: MediaKind.audio,
          fileName: fileName,
          duration: dur,
          fileSize: out.lengthSync(),
          artworkFileName: artName,
        ));
      } catch (_) {}
    }

    if (tracks.isNotEmpty) {
      playlists.add(MediaPlaylist(
        id: _uuid.v4(),
        name: 'Başlangıç Seçkisi',
        detail: 'Cihazında çevrimdışı hazır parçalar',
        trackIDs: tracks.map((e) => e.id).toList(),
        coverTrackID: tracks.first.id,
        isPinned: true,
      ));
      await _persistState();
    }
  }

  Future<Map<String, dynamic>> _inspectFile(String path) async {
    final res = await _ritimChannel.invokeMethod<Map<dynamic, dynamic>>(
      'inspectMedia',
      {'path': path, 'artworkDir': _artworkDir.path},
    );
    return res?.map((k, v) => MapEntry(k.toString(), v)) ?? {};
  }

  String filePathFor(MediaTrack track) => '${_libraryDir.path}/${track.fileName}';

  String? artworkPathFor(MediaTrack track) {
    final art = track.artworkFileName;
    if (art == null || art.isEmpty) return null;
    if (art.contains('/') || art.contains('\\')) return art;
    return '${_artworkDir.path}/$art';
  }

  // MARK: - Persistence

  Future<void> _loadState() async {
    try {
      if (!_stateFile.existsSync()) return;
      final obj = jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
      themeStyle = RitimThemeStyle.fromId(obj['theme'] as String?);
      wallpaper = RitimWallpaper.fromId(obj['wallpaper'] as String?);
      _healedV111 = obj['healedV111'] == true;
      maxConcurrency = ((obj['maxConcurrency'] as num?)?.toInt() ?? 4).clamp(2, 20);
      defaultFormat = DownloadFormat.fromRaw(obj['defaultFormat'] as String?);
      defaultQuality = DownloadQuality.fromRaw(obj['defaultQuality'] as String?);
      shuffleEnabled = obj['shuffleEnabled'] == true;
      playbackRate = (obj['playbackRate'] as num?)?.toDouble() ?? 1.0;
      final rep = obj['repeatMode'] as String?;
      repeatMode = RepeatMode.values.firstWhere(
        (e) => e.name == rep,
        orElse: () => RepeatMode.off,
      );

      tracks.clear();
      for (final raw in (obj['tracks'] as List<dynamic>? ?? const [])) {
        if (raw is Map<String, dynamic>) {
          final t = MediaTrack.fromJson(raw);
          if (t.id.isNotEmpty) tracks.add(t);
        }
      }

      playlists.clear();
      for (final raw in (obj['playlists'] as List<dynamic>? ?? const [])) {
        if (raw is Map<String, dynamic>) {
          final p = MediaPlaylist.fromJson(raw);
          if (p.id.isNotEmpty) playlists.add(p);
        }
      }

      final qIds = (obj['queueIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      final byId = {for (final t in tracks) t.id: t};
      queue
        ..clear()
        ..addAll(qIds.map((id) => byId[id]).whereType<MediaTrack>());
      final curId = obj['currentTrackId'] as String?;
      if (curId != null && byId.containsKey(curId)) {
        currentTrack = byId[curId];
        elapsed = (obj['lastElapsed'] as num?)?.toDouble() ?? 0;
        duration = currentTrack!.duration;
      }
    } catch (_) {}
  }

  Future<void> _persistState() async {
    try {
      final payload = {
        'theme': themeStyle.id,
        'wallpaper': wallpaper.id,
        'healedV111': _healedV111,
        'maxConcurrency': maxConcurrency,
        'defaultFormat': defaultFormat.name,
        'defaultQuality': defaultQuality.name,
        'shuffleEnabled': shuffleEnabled,
        'playbackRate': playbackRate,
        'repeatMode': repeatMode.name,
        'currentTrackId': currentTrack?.id,
        'lastElapsed': elapsed,
        'queueIds': queue.map((t) => t.id).toList(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'playlists': playlists.map((p) => p.toJson()).toList(),
      };
      await _stateFile.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _loadDownloads() async {
    try {
      if (!_downloadsFile.existsSync()) return;
      final list = jsonDecode(await _downloadsFile.readAsString()) as List<dynamic>;
      downloadEntries.clear();
      for (final raw in list.whereType<Map<String, dynamic>>()) {
        final e = DownloadEntry.fromJson(raw);
        if (e.status == DownloadStatus.downloading ||
            e.status == DownloadStatus.preparing) {
          e.status = DownloadStatus.queued;
          e.stage = null;
        }
        downloadEntries.add(e);
      }
    } catch (_) {}
  }

  Future<void> _healLegacyDownloadsAndStubs() async {
    var dirtyState = false;
    var dirtyDownloads = false;

    // Daha önce canlı radyo yayını (7/24) olarak hatalı inen <120 KB kırık segmentleri temizle
    final brokenTrackIds = <String>{};
    tracks.removeWhere((t) {
      final isTinyYoutubeStub = t.sourceURL != null &&
          t.sourceURL!.contains('youtube.com') &&
          t.fileSize > 0 &&
          t.fileSize < 120 * 1024;
      if (isTinyYoutubeStub) {
        brokenTrackIds.add(t.id);
        try {
          final f = File(filePathFor(t));
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
        dirtyState = true;
        return true;
      }
      return false;
    });

    if (brokenTrackIds.isNotEmpty) {
      queue.removeWhere((t) => brokenTrackIds.contains(t.id));
      if (currentTrack != null && brokenTrackIds.contains(currentTrack!.id)) {
        currentTrack = tracks.isNotEmpty ? tracks.first : null;
      }
    }

    downloadEntries.removeWhere((e) {
      final remove = (e.trackID != null && brokenTrackIds.contains(e.trackID)) ||
          ((e.expectedBytes ?? 999999) < 120 * 1024 &&
              e.status == DownloadStatus.completed);
      if (remove) dirtyDownloads = true;
      return remove;
    });

    // Önceki sürümden kalan HTTP 403 hatalı indirmeleri yeni motorla bir kez otomatik kuyruğa al
    if (!_healedV111) {
      _healedV111 = true;
      dirtyState = true;
      for (final e in downloadEntries) {
        if (e.status == DownloadStatus.failed &&
            (e.error?.contains('403') ?? false)) {
          e.status = DownloadStatus.queued;
          e.error = null;
          e.progress = 0;
          e.retryCount += 1;
          dirtyDownloads = true;
        }
      }
    }

    if (dirtyState) await _persistState();
    if (dirtyDownloads) await _persistDownloads();
  }

  Future<void> _persistDownloads() async {
    try {
      await _downloadsFile.writeAsString(
        jsonEncode(downloadEntries.take(5000).map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _loadListening() async {
    try {
      if (!_listeningFile.existsSync()) return;
      final list = jsonDecode(await _listeningFile.readAsString()) as List<dynamic>;
      _listeningByDay.clear();
      for (final raw in list.whereType<Map<String, dynamic>>()) {
        final d = ListeningDay.fromJson(raw);
        if (d.dayKey.isNotEmpty) _listeningByDay[d.dayKey] = d;
      }
    } catch (_) {}
  }

  Future<void> _persistListening() async {
    try {
      final sorted = _listeningByDay.values.toList()
        ..sort((a, b) => a.dayKey.compareTo(b.dayKey));
      final kept =
          sorted.length > 366 ? sorted.sublist(sorted.length - 366) : sorted;
      await _listeningFile.writeAsString(
        jsonEncode(kept.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _loadAiState() async {
    try {
      if (!_aiFile.existsSync()) return;
      final obj = jsonDecode(await _aiFile.readAsString()) as Map<String, dynamic>;
      if (obj['config'] is Map<String, dynamic>) {
        aiConfig =
            AIConnectionConfig.fromJson(obj['config'] as Map<String, dynamic>);
      }
      aiMessages.clear();
      for (final m in (obj['messages'] as List<dynamic>? ?? const [])) {
        if (m is Map<String, dynamic>) aiMessages.add(AIMessage.fromJson(m));
      }
      aiModels = (obj['models'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RitimAIModel.fromJson)
          .toList();
      if (obj['dailyMix'] is Map<String, dynamic>) {
        dailyMix = AIDailyMix.fromJson(obj['dailyMix'] as Map<String, dynamic>);
      }
      excludedAiTrackIds
        ..clear()
        ..addAll(
          (obj['excluded'] as List<dynamic>? ?? const []).map((e) => e.toString()),
        );
      aiInsights.clear();
      for (final row in (obj['insights'] as List<dynamic>? ?? const [])) {
        if (row is Map<String, dynamic>) {
          final i = AITrackInsight.fromJson(row);
          if (i.trackID.isNotEmpty) aiInsights[i.trackID] = i;
        }
      }
    } catch (_) {}
  }

  Future<void> _persistAiState() async {
    try {
      final payload = {
        'config': aiConfig.toJson(),
        'models': aiModels.map((m) => m.toJson()).toList(),
        'messages': aiMessages.take(40).map((m) => m.toJson()).toList(),
        if (dailyMix != null) 'dailyMix': dailyMix!.toJson(),
        'excluded': excludedAiTrackIds.toList(),
        'insights': aiInsights.values.take(60).map((e) => e.toJson()).toList(),
      };
      await _aiFile.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  // MARK: - Theme & Settings

  Future<void> setTheme(RitimThemeStyle style) async {
    themeStyle = style;
    await _persistState();
    notifyListeners();
  }

  Future<void> setWallpaper(RitimWallpaper next) async {
    wallpaper = next;
    await _persistState();
    notifyListeners();
  }

  Future<void> cycleWallpaper() async {
    final idx = RitimWallpaper.values.indexOf(wallpaper);
    final next = RitimWallpaper.values[(idx + 1) % RitimWallpaper.values.length];
    await setWallpaper(next);
  }

  Future<void> setMaxConcurrency(int value) async {
    maxConcurrency = value.clamp(2, 20);
    await _persistState();
    _pumpDownloads();
    notifyListeners();
  }

  Future<void> setDefaultDownloadPrefs({
    DownloadFormat? format,
    DownloadQuality? quality,
  }) async {
    if (format != null) defaultFormat = format;
    if (quality != null) defaultQuality = quality;
    await _persistState();
    notifyListeners();
  }

  // MARK: - Listening Analytics

  static String dayKeyFor(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  List<ListeningDay> recentDays(int count, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    return List.generate(count, (idx) {
      final d = base.subtract(Duration(days: count - 1 - idx));
      final key = dayKeyFor(d);
      return _listeningByDay[key] ?? ListeningDay(dayKey: key);
    });
  }

  double totalSecondsForDays(int count, {DateTime? now}) {
    return recentDays(count, now: now).fold<double>(0, (s, d) => s + d.seconds);
  }

  void recordListeningSeconds(String trackId, double secs, {DateTime? at}) {
    if (!secs.isFinite || secs <= 0 || secs > 15) return;
    final key = dayKeyFor(at ?? DateTime.now());
    final day = _listeningByDay.putIfAbsent(key, () => ListeningDay(dayKey: key));
    day.seconds += secs;
    day.trackSeconds[trackId] = (day.trackSeconds[trackId] ?? 0) + secs;
  }

  // MARK: - Playback Engine

  void _restorePlaybackSession() {
    if (currentTrack == null) return;
    if (!enableNativePlayer) return;
    _loadVideoController(currentTrack!, autoPlay: false, initialSeek: elapsed);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final now = DateTime.now();
      if (sleepDeadline != null && now.isAfter(sleepDeadline!)) {
        sleepDeadline = null;
        sleepMinutes = 0;
        await pause();
        notifyListeners();
      }

      if (enableNativePlayer && videoController != null) {
        final val = videoController!.value;
        if (val.isInitialized) {
          elapsed = val.position.inMilliseconds / 1000.0;
          final d = val.duration.inMilliseconds / 1000.0;
          if (d > 0) duration = d;
          isPlaying = val.isPlaying;

          if (val.isPlaying && currentTrack != null) {
            final dt = _lastTickAt == null
                ? 1.0
                : (now.difference(_lastTickAt!).inMilliseconds / 1000.0)
                    .clamp(0.1, 3.0);
            recordListeningSeconds(currentTrack!.id, dt, at: now);
            if (elapsed - _lastSavedPosAt >= 15 || elapsed < _lastSavedPosAt) {
              _lastSavedPosAt = elapsed;
              unawaited(_persistListening());
              unawaited(_persistState());
            }
          }

          final reachedEnd = val.isCompleted ||
              (val.duration.inMilliseconds > 500 &&
                  val.position >=
                      val.duration - const Duration(milliseconds: 600) &&
                  !val.isPlaying &&
                  elapsed > 1.0);
          if (reachedEnd && !_isHandlingCompletion) {
            await _handleTrackCompleted();
          }
        }
      } else if (isPlaying && currentTrack != null) {
        elapsed = (elapsed + playbackRate).clamp(0, duration > 0 ? duration : 200);
        recordListeningSeconds(currentTrack!.id, 1.0, at: now);
        if (duration > 0 && elapsed >= duration) {
          await _handleTrackCompleted();
        }
      }
      _lastTickAt = now;
      notifyListeners();
    });
  }

  void _onNativePlayerChanged() {
    final ctrl = videoController;
    if (ctrl == null || !enableNativePlayer || _isHandlingCompletion) return;
    final val = ctrl.value;
    if (!val.isInitialized) return;
    final posSec = val.position.inMilliseconds / 1000.0;
    final durSec = val.duration.inMilliseconds / 1000.0;
    if (durSec > 0) duration = durSec;
    elapsed = posSec;
    final reachedEnd = val.isCompleted ||
        (val.duration.inMilliseconds > 500 &&
            val.position >= val.duration - const Duration(milliseconds: 600) &&
            !val.isPlaying &&
            posSec > 1.0);
    if (reachedEnd) {
      unawaited(_handleTrackCompleted());
    }
  }

  Future<void> _handleTrackCompleted() async {
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;
    try {
      if (repeatMode == RepeatMode.one && currentTrack != null) {
        await seekTo(0);
        await play();
        return;
      }
      if (sleepMinutes == -1) {
        sleepMinutes = 0;
        sleepDeadline = null;
        await pause();
        return;
      }
      await nextTrack();
    } finally {
      _isHandlingCompletion = false;
    }
  }

  Future<void> playTrack(MediaTrack track, {List<MediaTrack>? context}) async {
    if (context != null && context.isNotEmpty) {
      queue
        ..clear()
        ..addAll(context);
    } else if (!queue.any((t) => t.id == track.id)) {
      queue.add(track);
    }
    await _loadTrack(track, autoPlay: true);
    _rebuildShuffleBag();
    unawaited(_maybeExtendDJ());
  }

  Future<void> _loadTrack(MediaTrack track, {bool autoPlay = true}) async {
    final idx = tracks.indexWhere((t) => t.id == track.id);
    if (idx >= 0) {
      tracks[idx].playCount += 1;
      tracks[idx].lastPlayedAt = DateTime.now();
      currentTrack = tracks[idx];
    } else {
      currentTrack = track;
    }
    elapsed = 0;
    duration = track.duration;
    isLoadingMedia = true;
    isPlaying = autoPlay;
    notifyListeners();

    if (enableNativePlayer) {
      await _loadVideoController(track, autoPlay: autoPlay);
    } else {
      isLoadingMedia = false;
    }
    unawaited(_syncNotification());
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _loadVideoController(
    MediaTrack track, {
    required bool autoPlay,
    double initialSeek = 0,
  }) async {
    final old = videoController;
    videoController = null;
    if (old != null) {
      try {
        old.removeListener(_onNativePlayerChanged);
        await old.dispose();
      } catch (_) {}
    }

    final f = File(filePathFor(track));
    if (!f.existsSync()) {
      isLoadingMedia = false;
      isPlaying = false;
      statusBanner = '${track.title} dosyası bulunamadı.';
      notifyListeners();
      return;
    }

    final ctrl = VideoPlayerController.file(
      f,
      videoPlayerOptions: VideoPlayerOptions(
        allowBackgroundPlayback: true,
        mixWithOthers: false,
      ),
    );
    videoController = ctrl;
    try {
      await ctrl.initialize();
      ctrl.addListener(_onNativePlayerChanged);
      await ctrl.setPlaybackSpeed(playbackRate);
      if (initialSeek > 0 && initialSeek < ctrl.value.duration.inSeconds) {
        await ctrl.seekTo(Duration(milliseconds: (initialSeek * 1000).round()));
      }
      final d = ctrl.value.duration.inMilliseconds / 1000.0;
      if (d > 0) {
        duration = d;
        track.duration = d;
      }
      if (autoPlay) {
        await ctrl.play();
        isPlaying = true;
      } else {
        isPlaying = false;
      }
    } catch (e) {
      isPlaying = false;
      statusBanner = 'Medya açılamadı: $e';
    } finally {
      isLoadingMedia = false;
      unawaited(_syncNotification());
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (currentTrack == null) {
      if (tracks.isNotEmpty) {
        await playTrack(tracks.first, context: tracks);
      }
      return;
    }
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (enableNativePlayer && videoController != null) {
      await videoController!.play();
    }
    isPlaying = true;
    unawaited(_syncNotification());
    notifyListeners();
  }

  Future<void> pause() async {
    if (enableNativePlayer && videoController != null) {
      await videoController!.pause();
    }
    isPlaying = false;
    await _persistListening();
    await _persistState();
    unawaited(_syncNotification());
    notifyListeners();
  }

  Future<void> seekTo(double seconds) async {
    final clamped = duration > 0
        ? seconds.clamp(0.0, duration)
        : math.max(0.0, seconds);
    elapsed = clamped;
    if (enableNativePlayer && videoController != null) {
      await videoController!
          .seekTo(Duration(milliseconds: (clamped * 1000).round()));
    }
    notifyListeners();
  }

  Future<void> setPlaybackRate(double rate) async {
    playbackRate = rate.clamp(0.5, 2.0);
    if (enableNativePlayer && videoController != null) {
      await videoController!.setPlaybackSpeed(playbackRate);
    }
    await _persistState();
    notifyListeners();
  }

  void toggleShuffle() {
    shuffleEnabled = !shuffleEnabled;
    _rebuildShuffleBag();
    unawaited(_persistState());
    notifyListeners();
  }

  void cycleRepeatMode() {
    repeatMode = switch (repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    unawaited(_persistState());
    notifyListeners();
  }

  void setSleepTimer(int minutes) {
    sleepMinutes = minutes;
    if (minutes > 0) {
      sleepDeadline = DateTime.now().add(Duration(minutes: minutes));
    } else {
      sleepDeadline = null;
    }
    notifyListeners();
  }

  void _rebuildShuffleBag() {
    _shuffleRemaining.clear();
    final curId = currentTrack?.id;
    final ids = queue.map((t) => t.id).where((id) => id != curId).toList()
      ..shuffle();
    _shuffleRemaining.addAll(ids);
  }

  Future<void> nextTrack() async {
    if (queue.isEmpty) return;
    if (shuffleEnabled) {
      if (_shuffleRemaining.isEmpty) {
        if (repeatMode == RepeatMode.all) {
          _rebuildShuffleBag();
        } else {
          await pause();
          return;
        }
      }
      if (_shuffleRemaining.isNotEmpty) {
        if (currentTrack != null) _shuffleHistory.add(currentTrack!.id);
        final nextId = _shuffleRemaining.removeAt(0);
        final next = queue.firstWhere(
          (t) => t.id == nextId,
          orElse: () => queue.first,
        );
        await _loadTrack(next, autoPlay: true);
        unawaited(_maybeExtendDJ());
        return;
      }
    }

    final idx = currentTrack == null
        ? -1
        : queue.indexWhere((t) => t.id == currentTrack!.id);
    if (idx + 1 < queue.length) {
      await _loadTrack(queue[idx + 1], autoPlay: true);
      unawaited(_maybeExtendDJ());
    } else if (repeatMode == RepeatMode.all && queue.isNotEmpty) {
      await _loadTrack(queue.first, autoPlay: true);
    } else {
      await pause();
    }
  }

  Future<void> previousTrack() async {
    if (elapsed > 4) {
      await seekTo(0);
      return;
    }
    if (shuffleEnabled && _shuffleHistory.isNotEmpty) {
      final prevId = _shuffleHistory.removeLast();
      final match = queue.where((t) => t.id == prevId);
      if (match.isNotEmpty) {
        await _loadTrack(match.first, autoPlay: true);
        return;
      }
    }
    final idx = currentTrack == null
        ? 0
        : queue.indexWhere((t) => t.id == currentTrack!.id);
    if (idx > 0) {
      await _loadTrack(queue[idx - 1], autoPlay: true);
    } else if (repeatMode == RepeatMode.all && queue.isNotEmpty) {
      await _loadTrack(queue.last, autoPlay: true);
    } else {
      await seekTo(0);
    }
  }

  void enqueue(MediaTrack track) {
    if (!queue.any((t) => t.id == track.id)) {
      queue.add(track);
      if (shuffleEnabled) _shuffleRemaining.add(track.id);
      if (currentTrack == null) {
        unawaited(_loadTrack(track, autoPlay: false));
      }
      unawaited(_persistState());
      notifyListeners();
    }
  }

  void enqueueNext(MediaTrack track) {
    if (currentTrack == null) {
      enqueue(track);
      return;
    }
    if (currentTrack!.id == track.id) return;
    queue.removeWhere((t) => t.id == track.id);
    final idx = queue.indexWhere((t) => t.id == currentTrack!.id);
    queue.insert((idx < 0 ? queue.length - 1 : idx) + 1, track);
    if (shuffleEnabled) {
      _shuffleRemaining.remove(track.id);
      _shuffleRemaining.insert(0, track.id);
    }
    unawaited(_persistState());
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= queue.length) return;
    final removing = queue.removeAt(index);
    if (currentTrack?.id == removing.id) {
      if (queue.isNotEmpty) {
        final nextIdx = index.clamp(0, queue.length - 1);
        unawaited(_loadTrack(queue[nextIdx], autoPlay: isPlaying));
      } else {
        unawaited(pause());
        currentTrack = null;
      }
    }
    unawaited(_persistState());
    notifyListeners();
  }

  void moveQueue(int oldIndex, int newIndex, {bool alreadyAdjusted = false}) {
    if (!alreadyAdjusted && oldIndex < newIndex) newIndex -= 1;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex.clamp(0, queue.length), item);
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _syncNotification() async {
    if (!enableNativePlayer) return;
    try {
      await _ritimChannel.invokeMethod('updateNotification', {
        'title': currentTrack?.title ?? '',
        'artist': currentTrack?.artist ?? '',
        'isPlaying': isPlaying,
        'active': currentTrack != null,
        'artworkPath':
            currentTrack != null ? artworkPathFor(currentTrack!) : null,
        'durationMs': (duration * 1000).round(),
        'positionMs': (elapsed * 1000).round(),
        'playbackSpeed': playbackRate,
        'activeDownloads': downloadEntries.where((e) => e.isActive).length,
      });
    } catch (_) {}
  }

  // MARK: - Library Mutations & Collections

  void toggleFavorite(String trackId) {
    final idx = tracks.indexWhere((t) => t.id == trackId);
    if (idx < 0) return;
    tracks[idx].isFavorite = !tracks[idx].isFavorite;
    if (currentTrack?.id == trackId) {
      currentTrack = tracks[idx];
    }
    unawaited(_persistState());
    notifyListeners();
  }

  void updateTrackMeta(
    String trackId, {
    required String title,
    required String artist,
    String? album,
  }) {
    final idx = tracks.indexWhere((t) => t.id == trackId);
    if (idx < 0) return;
    tracks[idx].title = title.trim().isEmpty ? tracks[idx].title : title.trim();
    tracks[idx].artist =
        artist.trim().isEmpty ? 'Bilinmeyen sanatçı' : artist.trim();
    tracks[idx].album = album?.trim().isEmpty == true ? null : album?.trim();
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> deleteTrack(String trackId) async {
    final idx = tracks.indexWhere((t) => t.id == trackId);
    if (idx < 0) return;
    final removed = tracks.removeAt(idx);
    queue.removeWhere((t) => t.id == trackId);
    for (final pl in playlists) {
      pl.trackIDs.removeWhere((id) => id == trackId);
    }
    if (currentTrack?.id == trackId) {
      if (queue.isNotEmpty) {
        await _loadTrack(queue.first, autoPlay: false);
      } else {
        await pause();
        currentTrack = null;
      }
    }
    try {
      final f = File(filePathFor(removed));
      if (f.existsSync()) await f.delete();
    } catch (_) {}
    await lyrics.remove(trackId);
    await _persistState();
    notifyListeners();
  }

  MediaPlaylist createPlaylist(
    String name, {
    List<String> trackIds = const [],
    String? detail,
  }) {
    final clean = name.trim().isEmpty ? 'Yeni Liste' : name.trim();
    final validSet = tracks.map((t) => t.id).toSet();
    final filteredIds =
        trackIds.where(validSet.contains).toSet().toList();
    final pl = MediaPlaylist(
      id: _uuid.v4(),
      name: clean,
      detail: detail,
      trackIDs: filteredIds,
      coverTrackID: filteredIds.isNotEmpty ? filteredIds.first : null,
    );
    playlists.insert(0, pl);
    unawaited(_persistState());
    notifyListeners();
    return pl;
  }

  void renamePlaylist(String playlistId, String newName) {
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0 || newName.trim().isEmpty) return;
    playlists[idx].name = newName.trim();
    unawaited(_persistState());
    notifyListeners();
  }

  void deletePlaylist(String playlistId) {
    playlists.removeWhere((p) => p.id == playlistId);
    unawaited(_persistState());
    notifyListeners();
  }

  void addTrackToPlaylist(String playlistId, String trackId) {
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    if (!playlists[idx].trackIDs.contains(trackId)) {
      playlists[idx].trackIDs.add(trackId);
      playlists[idx].coverTrackID ??= trackId;
      unawaited(_persistState());
      notifyListeners();
    }
  }

  void removeTrackFromPlaylist(String playlistId, String trackId) {
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    playlists[idx].trackIDs.remove(trackId);
    unawaited(_persistState());
    notifyListeners();
  }

  List<ArtistGroup> get artistGroups {
    final byArtist = <String, List<MediaTrack>>{};
    for (final t in tracks.where((e) => e.kind == MediaKind.audio)) {
      final name = t.artist.trim().isEmpty ? 'Bilinmeyen sanatçı' : t.artist.trim();
      byArtist.putIfAbsent(name, () => []).add(t);
    }
    return byArtist.entries
        .map((e) => ArtistGroup(
              name: e.key,
              tracks: e.value,
              artworkPath: e.value
                  .map(artworkPathFor)
                  .whereType<String>()
                  .firstOrNull,
            ))
        .toList()
      ..sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
  }

  List<AlbumGroup> get albumGroups {
    final map = <String, List<MediaTrack>>{};
    for (final t in tracks.where((e) => e.kind == MediaKind.audio)) {
      final al = t.album?.trim();
      if (al == null || al.isEmpty) continue;
      map.putIfAbsent('$al|${t.artist}', () => []).add(t);
    }
    return map.entries.map((e) {
      final sample = e.value.first;
      return AlbumGroup(
        title: sample.album!,
        artist: sample.artist,
        tracks: e.value,
        artworkPath:
            e.value.map(artworkPathFor).whereType<String>().firstOrNull,
      );
    }).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  // MARK: - Device File Import & Scan

  Future<int> pickAndImportLocalFiles() async {
    final picked = await _ritimChannel.invokeMethod<List<dynamic>>(
      'pickMediaFiles',
      {'destDir': _libraryDir.path},
    );
    if (picked == null || picked.isEmpty) return 0;

    var added = 0;
    for (final row in picked.whereType<Map<dynamic, dynamic>>()) {
      final path = row['path']?.toString();
      final originalName = row['originalName']?.toString() ?? 'parca.m4a';
      final size = (row['size'] as num?)?.toInt() ?? 0;
      if (path == null) continue;
      final file = File(path);
      if (!file.existsSync() || size <= 0) continue;

      final ext = originalName.contains('.')
          ? originalName.split('.').last.toLowerCase()
          : 'm4a';
      final isVideo = ext == 'mp4' || ext == 'mov';
      final fallbackTitle = originalName.contains('.')
          ? originalName.substring(0, originalName.lastIndexOf('.'))
          : originalName;

      var info = <String, dynamic>{};
      try {
        info = await _inspectFile(path);
      } catch (_) {}

      final hasVideoMeta = info['hasVideo'] == true;
      final track = MediaTrack(
        id: _uuid.v4(),
        title: (info['title'] as String?)?.trim().isNotEmpty == true
            ? info['title'] as String
            : fallbackTitle,
        artist: (info['artist'] as String?)?.trim().isNotEmpty == true
            ? info['artist'] as String
            : 'Yerel Medya',
        album: (info['album'] as String?)?.trim(),
        kind: (isVideo || hasVideoMeta) ? MediaKind.video : MediaKind.audio,
        fileName: file.uri.pathSegments.last,
        duration: (info['durationSeconds'] as num?)?.toDouble() ?? 0,
        fileSize: size,
        artworkFileName: info['artworkPath'] as String?,
        trackNumber: (info['trackNumber'] as num?)?.toInt(),
        discNumber: (info['discNumber'] as num?)?.toInt(),
      );
      tracks.insert(0, track);
      added++;
    }
    if (added > 0) {
      statusBanner = '$added dosya kütüphaneye eklendi.';
      await _persistState();
      notifyListeners();
    }
    return added;
  }

  Future<int> rescanAllMetadata() async {
    if (isScanningMetadata) return 0;
    isScanningMetadata = true;
    notifyListeners();
    var updated = 0;
    try {
      for (final track in tracks) {
        final f = File(filePathFor(track));
        if (!f.existsSync()) continue;
        try {
          final info = await _inspectFile(f.path);
          final d = (info['durationSeconds'] as num?)?.toDouble() ?? 0;
          if (d > 0 && (track.duration == 0 || (d - track.duration).abs() > 1)) {
            track.duration = d;
            updated++;
          }
          final art = info['artworkPath'] as String?;
          if (art != null && track.artworkFileName == null) {
            track.artworkFileName = art;
            updated++;
          }
          final album = (info['album'] as String?)?.trim();
          if (album != null && album.isNotEmpty && track.album == null) {
            track.album = album;
            updated++;
          }
        } catch (_) {}
      }
      await _persistState();
    } finally {
      isScanningMetadata = false;
      notifyListeners();
    }
    return updated;
  }

  // MARK: - Backup Export / Import (.ritimbackup)

  Future<bool> exportBackup({bool includeAudio = true}) async {
    final archive = Archive();
    final manifest = jsonEncode({
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'lyrics': lyrics.items.values.map((l) => l.toJson()).toList(),
      'listening': _listeningByDay.values.map((d) => d.toJson()).toList(),
    });
    final manifestBytes = utf8.encode(manifest);
    archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    if (includeAudio) {
      for (final t in tracks) {
        final f = File(filePathFor(t));
        if (f.existsSync()) {
          final bytes = await f.readAsBytes();
          archive.addFile(
              ArchiveFile('media/${t.fileName}', bytes.length, bytes));
        }
      }
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) return false;
    final tmp = File(
        '${_tempDir.path}/ritim_yedek_${DateTime.now().millisecondsSinceEpoch}.ritimbackup');
    await tmp.writeAsBytes(zipBytes);

    final ok = await _ritimChannel.invokeMethod<bool>('exportBackupFile', {
      'path': tmp.path,
      'suggestedName':
          'ritim-yedek-${dayKeyFor(DateTime.now())}.ritimbackup',
    });
    return ok == true;
  }

  Future<String> importBackupFromDevice() async {
    final path = await _ritimChannel.invokeMethod<String>(
      'pickBackupFile',
      {'destDir': _tempDir.path},
    );
    if (path == null) return 'İptal edildi.';
    final file = File(path);
    if (!file.existsSync()) return 'Yedek dosyası okunamadı.';

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const RitimException('Geçerli bir .ritimbackup paketi değil.');
    }
    final manifest =
        jsonDecode(utf8.decode(manifestFile.content as List<int>))
            as Map<String, dynamic>;

    final existingIds = tracks.map((t) => t.id).toSet();
    final existingSigs = tracks
        .map((t) => '${t.title.toLowerCase()}|${t.artist.toLowerCase()}')
        .toSet();

    var addedTracks = 0;
    var skippedTracks = 0;
    for (final raw in (manifest['tracks'] as List<dynamic>? ?? const [])) {
      if (raw is! Map<String, dynamic>) continue;
      final t = MediaTrack.fromJson(raw);
      final sig = '${t.title.toLowerCase()}|${t.artist.toLowerCase()}';
      if (existingIds.contains(t.id) || existingSigs.contains(sig)) {
        skippedTracks++;
        continue;
      }
      final mediaEntry = archive.findFile('media/${t.fileName}');
      if (mediaEntry != null) {
        final dest = File('${_libraryDir.path}/${t.fileName}');
        await dest.writeAsBytes(mediaEntry.content as List<int>);
      }
      tracks.add(t);
      existingIds.add(t.id);
      addedTracks++;
    }

    final existingPlIds = playlists.map((p) => p.id).toSet();
    for (final raw in (manifest['playlists'] as List<dynamic>? ?? const [])) {
      if (raw is! Map<String, dynamic>) continue;
      final p = MediaPlaylist.fromJson(raw);
      if (!existingPlIds.contains(p.id)) {
        playlists.add(p);
      }
    }

    await _persistState();
    notifyListeners();
    return '$addedTracks parça içe aktarıldı'
        '${skippedTracks > 0 ? ", $skippedTracks yineleme atlandı" : ""}.';
  }

  // MARK: - YouTube Search & Preview

  Future<void> searchYouTube(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    isSearchingYouTube = true;
    searchError = null;
    lastSearchQuery = clean;
    notifyListeners();
    try {
      searchResults = await catalog.search(clean, limit: 40);
    } catch (e) {
      searchError = e.toString();
    } finally {
      isSearchingYouTube = false;
      notifyListeners();
    }
  }

  Future<void> previewYouTubePlaylist(String rawUrl) async {
    isLoadingPlaylist = true;
    playlistPreview = null;
    statusBanner = null;
    notifyListeners();
    try {
      final url = MediaURLPolicy.validatedPlaylist(rawUrl);
      playlistPreview = await catalog.previewPlaylist(url, limit: 100);
    } catch (e) {
      statusBanner = e.toString();
    } finally {
      isLoadingPlaylist = false;
      notifyListeners();
    }
  }

  // MARK: - Downloads Queue & Worker Pool

  Future<DownloadEntry> enqueueDownload(
    String rawUrl, {
    DownloadFormat? format,
    DownloadQuality? quality,
    String? title,
    String? artist,
    String? playlistId,
    String? batchName,
  }) async {
    final fmt = format ?? defaultFormat;
    final qual = quality ?? defaultQuality;
    final canonical = MediaURLPolicy.canonicalInput(rawUrl, stripMix: true);
    final key = MediaURLPolicy.downloadKey(
      canonical.toString(),
      format: fmt,
      quality: qual,
    );

    if (key != null) {
      final dup = downloadEntries.where((e) {
        final ek = MediaURLPolicy.downloadKey(
          e.sourceURL,
          format: e.format,
          quality: e.quality,
        );
        return ek == key && (e.isActive || e.status == DownloadStatus.completed);
      });
      if (dup.isNotEmpty) {
        final existing = dup.first;
        if (playlistId != null && existing.trackID != null) {
          addTrackToPlaylist(playlistId, existing.trackID!);
        }
        return existing;
      }
    }

    final entry = DownloadEntry(
      id: _uuid.v4(),
      title: (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : (MediaURLPolicy.isYouTube(canonical)
              ? 'YouTube Parçası'
              : canonical.pathSegments.last),
      artist: artist,
      sourceURL: canonical.toString(),
      format: fmt,
      quality: qual,
      status: DownloadStatus.queued,
      playlistID: playlistId,
      batchName: batchName,
    );

    downloadEntries.insert(0, entry);
    if (downloadEntries.length > 5000) {
      downloadEntries.removeRange(5000, downloadEntries.length);
    }
    unawaited(_persistDownloads());
    _pumpDownloads();
    notifyListeners();
    return entry;
  }

  Future<int> enqueueSelectedPlaylistItems(
    List<PlaylistItem> items, {
    required String playlistName,
    DownloadFormat? format,
    DownloadQuality? quality,
    bool createTargetPlaylist = true,
  }) async {
    String? plId;
    if (createTargetPlaylist) {
      final pl = createPlaylist(
        playlistName,
        detail: 'YouTube oynatma listesinden indirildi',
      );
      plId = pl.id;
    }
    var count = 0;
    for (final item in items) {
      await enqueueDownload(
        item.url,
        format: format ?? defaultFormat,
        quality: quality ?? defaultQuality,
        title: item.title,
        artist: item.artist,
        playlistId: plId,
        batchName: playlistName,
      );
      count++;
    }
    return count;
  }

  void cancelDownload(String entryId) {
    _cancelledIds.add(entryId);
    final idx = downloadEntries.indexWhere((e) => e.id == entryId);
    if (idx >= 0) {
      downloadEntries[idx].status = DownloadStatus.cancelled;
      downloadEntries[idx].stage = null;
      unawaited(_persistDownloads());
      notifyListeners();
    }
  }

  void retryDownload(String entryId) {
    _cancelledIds.remove(entryId);
    final idx = downloadEntries.indexWhere((e) => e.id == entryId);
    if (idx < 0) return;
    downloadEntries[idx].status = DownloadStatus.queued;
    downloadEntries[idx].error = null;
    downloadEntries[idx].progress = 0;
    downloadEntries[idx].retryCount += 1;
    unawaited(_persistDownloads());
    _pumpDownloads();
    notifyListeners();
  }

  void clearFinishedDownloads() {
    downloadEntries.removeWhere((e) =>
        e.status == DownloadStatus.completed ||
        e.status == DownloadStatus.cancelled);
    unawaited(_persistDownloads());
    notifyListeners();
  }

  void _pumpDownloads() {
    while (_activeWorkerIds.length < maxConcurrency) {
      final next = downloadEntries.cast<DownloadEntry?>().firstWhere(
            (e) =>
                e != null &&
                e.status == DownloadStatus.queued &&
                !_activeWorkerIds.contains(e.id),
            orElse: () => null,
          );
      if (next == null) break;
      _activeWorkerIds.add(next.id);
      unawaited(_runDownloadWorker(next));
    }
  }

  Future<void> _runDownloadWorker(DownloadEntry entry) async {
    try {
      bool isCancelled() => _cancelledIds.contains(entry.id);
      if (isCancelled()) return;

      entry.status = DownloadStatus.preparing;
      entry.stage = DownloadStage.resolving;
      entry.progress = 0.04;
      unawaited(_syncNotification());
      notifyListeners();

      final canonical = Uri.parse(entry.sourceURL);
      final media = await downloader.resolve(
        canonical,
        format: entry.format,
        quality: entry.quality,
      );
      if (isCancelled()) return;

      entry.title = media.title;
      entry.artist = media.artist;
      entry.qualityNote = media.qualityNote;
      entry.status = DownloadStatus.downloading;
      entry.stage = DownloadStage.transferring;
      notifyListeners();

      final trackId = _uuid.v4();
      late File finalFile;
      late MediaKind kind;

      if (entry.format == DownloadFormat.mp4) {
        kind = MediaKind.video;
        final outFile = File('${_libraryDir.path}/$trackId.mp4');

        if (!MediaURLPolicy.isYouTube(canonical)) {
          final directStream = media.video ?? media.audio;
          await downloader.downloadStream(
            stream: directStream,
            destination: outFile,
            isCancelled: isCancelled,
            onProgress: (r, ex, bps) {
              entry.receivedBytes = r;
              entry.expectedBytes = ex > 0 ? ex : null;
              entry.bytesPerSecond = bps;
              entry.progress =
                  ex > 0 ? (0.08 + 0.86 * (r / ex)).clamp(0.08, 0.94) : 0.45;
              notifyListeners();
            },
          );
          finalFile = outFile;
          entry.resolvedQuality = 'MP4 Video';
        } else {
          var completedViaAdaptive = false;
          final adapVid = media.adaptiveVideo;
          final canTryHdMux = enableNativePlayer &&
              adapVid != null &&
              adapVid.contentLength > 0 &&
              adapVid.contentLength <=
                  NativeYouTubeDownloaderEngine.kMaxAdaptiveSingleRangeBytes &&
              (media.muxedVideo == null ||
                  (adapVid.resolution ?? 0) >
                      (media.muxedVideo!.resolution ?? 360));

          if (canTryHdMux) {
            final tmpVideo = File('${_tempDir.path}/${entry.id}_v.mp4');
            final tmpAudio = File('${_tempDir.path}/${entry.id}_a.m4a');
            try {
              await downloader.downloadStream(
                stream: adapVid,
                destination: tmpVideo,
                isCancelled: isCancelled,
                onProgress: (r, ex, bps) {
                  entry.receivedBytes = r;
                  entry.expectedBytes = ex > 0 ? ex : null;
                  entry.bytesPerSecond = bps;
                  entry.progress = ex > 0
                      ? (0.08 + 0.48 * (r / ex)).clamp(0.08, 0.56)
                      : 0.35;
                  notifyListeners();
                },
              );
              if (isCancelled()) return;

              final freshAudio = (media.videoId != null
                      ? await downloader.resolveFreshAdaptiveAudio(
                          media.videoId!,
                          entry.quality,
                        )
                      : null) ??
                  media.adaptiveAudio;

              if (freshAudio == null ||
                  freshAudio.contentLength <= 0 ||
                  freshAudio.contentLength >
                      NativeYouTubeDownloaderEngine
                          .kMaxAdaptiveSingleRangeBytes) {
                throw const RitimException(
                    'HD ses kanalı sınır dışı, birleşik MP4 akışına geçiliyor.');
              }

              await downloader.downloadStream(
                stream: freshAudio,
                destination: tmpAudio,
                isCancelled: isCancelled,
                onProgress: (r, ex, bps) {
                  entry.progress = ex > 0
                      ? (0.56 + 0.30 * (r / ex)).clamp(0.56, 0.86)
                      : 0.72;
                  notifyListeners();
                },
              );
              if (isCancelled()) return;

              entry.stage = DownloadStage.converting;
              entry.progress = 0.91;
              notifyListeners();
              await _ritimChannel.invokeMethod('muxAudioVideo', {
                'audioPath': tmpAudio.path,
                'videoPath': tmpVideo.path,
                'outPath': outFile.path,
              });
              if (outFile.existsSync() && outFile.lengthSync() > 16384) {
                completedViaAdaptive = true;
                finalFile = outFile;
                entry.resolvedQuality =
                    '${adapVid.resolution ?? 1080}p HD MP4';
              }
            } catch (_) {
              if (outFile.existsSync()) {
                try {
                  await outFile.delete();
                } catch (_) {}
              }
              if (isCancelled()) rethrow;
            } finally {
              if (tmpVideo.existsSync()) {
                try {
                  await tmpVideo.delete();
                } catch (_) {}
              }
              if (tmpAudio.existsSync()) {
                try {
                  await tmpAudio.delete();
                } catch (_) {}
              }
            }
          }

          if (!completedViaAdaptive) {
            final muxed = media.muxedVideo;
            if (muxed == null) {
              throw const RitimException(
                  'Bu video için indirilebilir MP4 video akışı bulunamadı.');
            }
            entry.stage = DownloadStage.transferring;
            notifyListeners();
            await downloader.downloadStream(
              stream: muxed,
              destination: outFile,
              isCancelled: isCancelled,
              onProgress: (r, ex, bps) {
                entry.receivedBytes = r;
                entry.expectedBytes = ex > 0 ? ex : null;
                entry.bytesPerSecond = bps;
                entry.progress = ex > 0
                    ? (0.08 + 0.85 * (r / ex)).clamp(0.08, 0.93)
                    : 0.45;
                notifyListeners();
              },
            );
            finalFile = outFile;
            entry.resolvedQuality = '${muxed.resolution ?? 360}p MP4';
            entry.qualityNote = null;
          }
        }
      } else {
        kind = MediaKind.audio;
        if (!MediaURLPolicy.isYouTube(canonical)) {
          final ext = media.audio.fileExtension;
          final outFile = File('${_libraryDir.path}/$trackId.$ext');
          await downloader.downloadStream(
            stream: media.audio,
            destination: outFile,
            isCancelled: isCancelled,
            onProgress: (r, ex, bps) {
              entry.receivedBytes = r;
              entry.expectedBytes = ex > 0 ? ex : null;
              entry.bytesPerSecond = bps;
              entry.progress =
                  ex > 0 ? (0.08 + 0.84 * (r / ex)).clamp(0.08, 0.92) : 0.45;
              notifyListeners();
            },
          );
          finalFile = outFile;
          entry.resolvedQuality = '192 kbps ${ext.toUpperCase()}';
        } else {
          final outFile = File('${_libraryDir.path}/$trackId.m4a');
          var completedViaAdaptive = false;
          final adapAud = media.adaptiveAudio;

          if (adapAud != null &&
              adapAud.contentLength > 0 &&
              adapAud.contentLength <=
                  NativeYouTubeDownloaderEngine.kMaxAdaptiveSingleRangeBytes) {
            try {
              await downloader.downloadStream(
                stream: adapAud,
                destination: outFile,
                isCancelled: isCancelled,
                onProgress: (r, ex, bps) {
                  entry.receivedBytes = r;
                  entry.expectedBytes = ex > 0 ? ex : null;
                  entry.bytesPerSecond = bps;
                  entry.progress = ex > 0
                      ? (0.08 + 0.84 * (r / ex)).clamp(0.08, 0.92)
                      : 0.45;
                  notifyListeners();
                },
              );
              if (outFile.existsSync() && outFile.lengthSync() > 8192) {
                completedViaAdaptive = true;
                final kbps = (adapAud.bitrate / 1000).round();
                entry.resolvedQuality =
                    '${kbps > 0 ? kbps : 128} kbps M4A (Ses)';
              }
            } catch (_) {
              if (outFile.existsSync()) {
                try {
                  await outFile.delete();
                } catch (_) {}
              }
              if (isCancelled()) rethrow;
            }
          }

          if (!completedViaAdaptive) {
            final muxed = media.muxedVideo;
            if (muxed == null) {
              throw const RitimException(
                  'Bu parça için indirilebilir ses akışı bulunamadı.');
            }
            final tmpMux = File('${_tempDir.path}/${entry.id}_mux.mp4');
            try {
              entry.stage = DownloadStage.transferring;
              notifyListeners();
              await downloader.downloadStream(
                stream: muxed,
                destination: tmpMux,
                isCancelled: isCancelled,
                onProgress: (r, ex, bps) {
                  entry.receivedBytes = r;
                  entry.expectedBytes = ex > 0 ? ex : null;
                  entry.bytesPerSecond = bps;
                  entry.progress = ex > 0
                      ? (0.08 + 0.78 * (r / ex)).clamp(0.08, 0.86)
                      : 0.45;
                  notifyListeners();
                },
              );
              if (isCancelled()) return;

              entry.stage = DownloadStage.converting;
              entry.progress = 0.91;
              notifyListeners();

              if (enableNativePlayer) {
                await _ritimChannel.invokeMethod('extractAudio', {
                  'inputPath': tmpMux.path,
                  'outPath': outFile.path,
                });
              } else {
                await tmpMux.copy(outFile.path);
              }
            } finally {
              if (tmpMux.existsSync()) {
                try {
                  await tmpMux.delete();
                } catch (_) {}
              }
            }
            if (!outFile.existsSync() || outFile.lengthSync() < 4096) {
              throw const RitimException('Ses dosyası ayrıştırılamadı.');
            }
            entry.resolvedQuality = '128 kbps M4A (Ses)';
            entry.qualityNote = null;
          }

          finalFile = outFile;
        }
      }

      if (isCancelled()) return;
      entry.stage = DownloadStage.saving;
      entry.progress = 0.96;
      notifyListeners();

      var dur = media.durationSeconds;
      String? artPath;
      if (media.videoId != null && media.videoId!.isNotEmpty) {
        try {
          final thumbFile = File('${_artworkDir.path}/yt_$trackId.jpg');
          await downloader.downloadThumbnail(media.videoId!, thumbFile);
          if (thumbFile.existsSync() && thumbFile.lengthSync() > 1024) {
            artPath = thumbFile.path;
          }
        } catch (_) {}
      }
      if (enableNativePlayer) {
        try {
          final info = await _inspectFile(finalFile.path);
          final d = (info['durationSeconds'] as num?)?.toDouble() ?? 0;
          if (d > 1) dur = d;
          artPath ??= info['artworkPath'] as String?;
        } catch (_) {}
      }

      final finalBytes = finalFile.lengthSync();
      entry.receivedBytes = finalBytes;
      entry.expectedBytes = finalBytes;

      final track = MediaTrack(
        id: trackId,
        title: media.title,
        artist: media.artist,
        kind: kind,
        fileName: finalFile.uri.pathSegments.last,
        duration: dur,
        sourceURL: entry.sourceURL,
        fileSize: finalBytes,
        downloadQuality: entry.quality,
        downloadEntryID: entry.id,
        artworkFileName: artPath,
      );

      tracks.insert(0, track);
      if (entry.playlistID != null) {
        addTrackToPlaylist(entry.playlistID!, track.id);
      }

      entry.trackID = track.id;
      entry.status = DownloadStatus.completed;
      entry.stage = null;
      entry.progress = 1.0;
      await _persistState();
      await _persistDownloads();
    } catch (e) {
      if (!_cancelledIds.contains(entry.id)) {
        entry.status = DownloadStatus.failed;
        entry.stage = null;
        entry.error = e.toString().replaceFirst('RitimException: ', '');
        await _persistDownloads();
      }
    } finally {
      _activeWorkerIds.remove(entry.id);
      _cancelledIds.remove(entry.id);
      unawaited(_syncNotification());
      notifyListeners();
      _pumpDownloads();
    }
  }

  // MARK: - Lyrics Operations

  Future<void> fetchLyricsFor(MediaTrack track) async {
    isFetchingLyrics = true;
    lyricsError = null;
    lyricsCandidates = [];
    notifyListeners();
    try {
      await lyrics.fetchBestForTrack(track);
    } catch (e) {
      lyricsError = e.toString();
    } finally {
      isFetchingLyrics = false;
      notifyListeners();
    }
  }

  Future<void> searchLyricsCandidates(String query) async {
    isFetchingLyrics = true;
    lyricsError = null;
    notifyListeners();
    try {
      lyricsCandidates = await lyrics.searchLRCLIB(query);
      if (lyricsCandidates.isEmpty) {
        lyricsError = 'Bu arama için söz eşleşmesi bulunamadı.';
      }
    } catch (e) {
      lyricsError = e.toString();
    } finally {
      isFetchingLyrics = false;
      notifyListeners();
    }
  }

  Future<bool> importLyricsFileFor(MediaTrack track) async {
    final res = await _ritimChannel.invokeMethod<Map<dynamic, dynamic>>(
      'pickLyricsFile',
    );
    if (res == null) return false;
    final text = res['text']?.toString() ?? '';
    final name = res['name']?.toString() ?? 'Dosyadan';
    await lyrics.saveCustom(track, rawText: text, sourceName: name);
    notifyListeners();
    return true;
  }

  Future<void> saveLyricsEdit(MediaTrack track, String raw) async {
    await lyrics.saveCustom(track, rawText: raw);
    notifyListeners();
  }

  Future<void> setLyricsOffset(MediaTrack track, double offset) async {
    await lyrics.setOffset(track.id, offset);
    notifyListeners();
  }

  // MARK: - AI Assistant & CLIProxyAPI

  Future<void> updateAiConnection({
    RitimAiBackendMode? mode,
    String? baseUrl,
    String? apiKey,
    String? authHeader,
    String? selectedModelId,
    bool? proactiveEnabled,
  }) async {
    if (mode != null) aiConfig.mode = mode;
    if (baseUrl != null) aiConfig.baseUrl = baseUrl.trim();
    if (apiKey != null) aiConfig.apiKey = apiKey.trim();
    if (authHeader != null) aiConfig.authHeader = authHeader;
    if (selectedModelId != null) aiConfig.selectedModelId = selectedModelId;
    if (proactiveEnabled != null) aiConfig.proactiveEnabled = proactiveEnabled;
    aiError = null;
    await _persistAiState();
    notifyListeners();
  }

  Future<void> loadAiModels() async {
    isLoadingModels = true;
    aiError = null;
    notifyListeners();
    try {
      final fetched = await aiClient.fetchAllModels(aiConfig);
      aiModels = fetched;
      if (aiConfig.selectedModelId.isEmpty && fetched.isNotEmpty) {
        aiConfig.selectedModelId = fetched.first.id;
      }
      await _persistAiState();
    } catch (e) {
      aiError = e.toString();
    } finally {
      isLoadingModels = false;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> _libraryMetadataForAi() {
    return tracks
        .where((t) => !excludedAiTrackIds.contains(t.id))
        .take(500)
        .map((t) => {
              'id': t.id,
              'title': t.title,
              'artist': t.artist,
              if (t.album != null) 'album': t.album,
              'kind': t.kind.name,
              'duration': t.duration.round(),
              'favorite': t.isFavorite,
              'plays': t.playCount,
            })
        .toList();
  }

  Map<String, dynamic> _listeningContextForAi({List<String> excludeIds = const []}) {
    final now = DateTime.now();
    final recent = tracks
        .where((t) => t.lastPlayedAt != null)
        .toList()
      ..sort((a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!));
    return {
      'local_time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'day_part': AIDayPart.forNow(now).rawValue,
      'recent_ids': recent.take(10).map((t) => t.id).toList(),
      'playlists': playlists
          .take(20)
          .map((p) => {'name': p.name, 'count': p.trackIDs.length})
          .toList(),
      if (currentTrack != null)
        'now_playing': {
          'id': currentTrack!.id,
          'title': currentTrack!.title,
          'artist': currentTrack!.artist,
        },
      if (queue.isNotEmpty) 'queue_ids': queue.take(100).map((t) => t.id).toList(),
      if (excludeIds.isNotEmpty) 'exclude_ids': excludeIds.take(300).toList(),
    };
  }

  Future<void> sendAiChat(String prompt) async {
    final clean = prompt.trim();
    if (clean.isEmpty || isSendingAi) return;
    if (aiConfig.selectedModelId.isEmpty) {
      aiError = 'Önce CLIProxyAPI bağlantısından bir model seç.';
      notifyListeners();
      return;
    }

    aiError = null;
    isSendingAi = true;
    aiMessages.add(AIMessage(id: _uuid.v4(), role: 'user', content: clean));
    notifyListeners();

    try {
      final hist = aiMessages
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .toList()
          .reversed
          .skip(1)
          .take(8)
          .toList()
          .reversed
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      final reply = await aiClient.chat(
        config: aiConfig,
        modelId: aiConfig.selectedModelId,
        prompt: clean,
        history: hist,
        libraryTracks: _libraryMetadataForAi(),
        listeningContext: _listeningContextForAi(),
        task: AITask.chat,
      );

      String? appliedNote;
      if (reply.playlist != null) {
        final selected = _tracksForIds(reply.playlist!.trackIDs);
        if (selected.isNotEmpty) {
          if (reply.action == AIAction.play) {
            await playTrack(selected.first, context: selected);
            appliedNote = '${selected.length} parçalık seçki çalınıyor';
          } else if (reply.action == AIAction.queueNext) {
            for (final t in selected.reversed) {
              enqueueNext(t);
            }
            appliedNote = '${selected.length} parça sıraya eklendi';
          }
        }
      }

      aiMessages.add(AIMessage(
        id: _uuid.v4(),
        role: 'assistant',
        content: reply.reply,
        model: reply.model,
        playlist: reply.playlist,
        searchQueries: reply.searchQueries,
        action: reply.action,
        appliedNote: appliedNote,
      ));
      await _persistAiState();
    } catch (e) {
      aiError = e.toString();
    } finally {
      isSendingAi = false;
      notifyListeners();
    }
  }

  Future<void> startAiDj(String moodPrompt) async {
    if (aiConfig.selectedModelId.isEmpty) {
      aiError = 'AI DJ için model seç.';
      notifyListeners();
      return;
    }
    if (tracks.isEmpty) {
      aiError = 'AI DJ için kütüphanede en az bir parça olmalı.';
      notifyListeners();
      return;
    }
    isDjLoading = true;
    aiError = null;
    notifyListeners();
    try {
      final reply = await aiClient.chat(
        config: aiConfig,
        modelId: aiConfig.selectedModelId,
        prompt: moodPrompt,
        history: const [],
        libraryTracks: _libraryMetadataForAi(),
        listeningContext: _listeningContextForAi(),
        task: AITask.dj,
      );
      final ids = reply.playlist?.trackIDs ?? const [];
      final resolved = _tracksForIds(ids);
      final selected = resolved.isNotEmpty
          ? resolved
          : tracks.take(math.min(10, tracks.length)).toList();
      djSession = AIDJSession(
        mood: moodPrompt,
        note: reply.reply,
        trackIDs: selected.map((t) => t.id).toList(),
      );
      await playTrack(selected.first, context: selected);
    } catch (e) {
      aiError = e.toString();
    } finally {
      isDjLoading = false;
      notifyListeners();
    }
  }

  void stopAiDj() {
    djSession = null;
    notifyListeners();
  }

  Future<void> _maybeExtendDJ() async {
    final session = djSession;
    if (session == null || session.isExtending || session.extensions >= 4) return;
    final curIdx = currentTrack == null
        ? -1
        : queue.indexWhere((t) => t.id == currentTrack!.id);
    if (curIdx < 0 || (queue.length - 1 - curIdx) > 2) return;
    if (aiConfig.selectedModelId.isEmpty) return;

    session.isExtending = true;
    notifyListeners();
    try {
      final exclude = queue.map((t) => t.id).toList()
        ..addAll(excludedAiTrackIds);
      final reply = await aiClient.chat(
        config: aiConfig,
        modelId: aiConfig.selectedModelId,
        prompt: session.mood,
        history: const [],
        libraryTracks: _libraryMetadataForAi(),
        listeningContext: _listeningContextForAi(excludeIds: exclude),
        task: AITask.djContinue,
      );
      final added = _tracksForIds(reply.playlist?.trackIDs ?? const []);
      for (final t in added) {
        enqueue(t);
        session.trackIDs.add(t.id);
      }
      session.extensions += 1;
      session.note = reply.reply;
    } catch (_) {} finally {
      session.isExtending = false;
      notifyListeners();
    }
  }

  Future<void> generateDailyMix() async {
    if (aiConfig.selectedModelId.isEmpty || tracks.isEmpty) return;
    isDailyLoading = true;
    notifyListeners();
    try {
      final reply = await aiClient.chat(
        config: aiConfig,
        modelId: aiConfig.selectedModelId,
        prompt: 'Bugün için kişisel karışım hazırla.',
        history: const [],
        libraryTracks: _libraryMetadataForAi(),
        listeningContext: _listeningContextForAi(),
        task: AITask.daily,
      );
      final ids = reply.playlist?.trackIDs ??
          tracks.take(math.min(10, tracks.length)).map((t) => t.id).toList();
      dailyMix = AIDailyMix(
        title: reply.playlist?.name ?? 'Günün Karışımı',
        note: reply.reply,
        trackIDs: ids,
        model: reply.model,
        createdAt: DateTime.now(),
        dayPart: AIDayPart.forNow().rawValue,
      );
      await _persistAiState();
    } catch (e) {
      aiError = e.toString();
    } finally {
      isDailyLoading = false;
      notifyListeners();
    }
  }

  Future<AITrackInsight?> fetchInsightFor(MediaTrack track) async {
    if (aiInsights.containsKey(track.id)) return aiInsights[track.id];
    if (aiConfig.selectedModelId.isEmpty) {
      aiError = 'Parça notu için önce Asistan sekmesinden model seç.';
      notifyListeners();
      return null;
    }
    isInsightLoading = true;
    notifyListeners();
    try {
      final reply = await aiClient.chat(
        config: aiConfig,
        modelId: aiConfig.selectedModelId,
        prompt: '${track.title} — ${track.artist}',
        history: const [],
        libraryTracks: _libraryMetadataForAi(),
        listeningContext: _listeningContextForAi(excludeIds: [track.id]),
        task: AITask.insight,
      );
      final insight = AITrackInsight(
        trackID: track.id,
        text: reply.reply,
        similarIDs: reply.playlist?.trackIDs ?? const [],
        searchQueries: reply.searchQueries,
        model: reply.model,
        createdAt: DateTime.now(),
      );
      aiInsights[track.id] = insight;
      await _persistAiState();
      return insight;
    } catch (e) {
      aiError = e.toString();
      return null;
    } finally {
      isInsightLoading = false;
      notifyListeners();
    }
  }

  void excludeTrackFromAi(String trackId) {
    excludedAiTrackIds.add(trackId);
    unawaited(_persistAiState());
    notifyListeners();
  }

  void clearExcludedAiTracks() {
    excludedAiTrackIds.clear();
    unawaited(_persistAiState());
    notifyListeners();
  }

  void clearAiChat() {
    aiMessages.clear();
    aiError = null;
    unawaited(_persistAiState());
    notifyListeners();
  }

  List<MediaTrack> _tracksForIds(List<String> ids) {
    final byId = {for (final t in tracks) t.id: t};
    return ids.map((id) => byId[id]).whereType<MediaTrack>().toList();
  }

  static String cleanExportFileNameFor(MediaTrack track) {
    final ext = track.fileName.contains('.')
        ? track.fileName.split('.').last.toLowerCase()
        : (track.kind == MediaKind.video ? 'mp4' : 'm4a');
    final artist = track.artist.trim();
    final title = track.title.trim().isEmpty ? 'Ritim Parça' : track.title.trim();
    final rawBase = (artist.isNotEmpty &&
            artist.toLowerCase() != 'bilinmeyen sanatçı' &&
            artist.toLowerCase() != 'yerel medya')
        ? '$artist - $title'
        : title;
    final safeBase = rawBase
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '${safeBase.isEmpty ? "Ritim_Parca" : safeBase}.$ext';
  }

  static String mimeTypeFor(MediaTrack track) {
    final ext = track.fileName.contains('.')
        ? track.fileName.split('.').last.toLowerCase()
        : (track.kind == MediaKind.video ? 'mp4' : 'm4a');
    if (track.kind == MediaKind.video || ext == 'mp4' || ext == 'm4v') {
      return 'video/mp4';
    }
    if (ext == 'mov') return 'video/quicktime';
    if (ext == 'mp3') return 'audio/mpeg';
    if (ext == 'wav') return 'audio/wav';
    if (ext == 'm4a' || ext == 'aac') return 'audio/mp4';
    return 'audio/*';
  }

  Future<bool> shareTrack(MediaTrack track) async {
    final path = filePathFor(track);
    if (!File(path).existsSync()) {
      statusBanner = '“${track.title}” dosyası cihazda bulunamadı.';
      notifyListeners();
      return false;
    }
    try {
      final ok = await _ritimChannel.invokeMethod<bool>('shareFile', {
        'path': path,
        'title': '${track.title} — ${track.artist}',
        'fileName': cleanExportFileNameFor(track),
        'mimeType': mimeTypeFor(track),
      });
      return ok ?? true;
    } catch (e) {
      statusBanner = 'Paylaşım başlatılamadı: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> saveTrackToDevice(MediaTrack track) async {
    final path = filePathFor(track);
    if (!File(path).existsSync()) {
      statusBanner = '“${track.title}” dosyası cihazda bulunamadı.';
      notifyListeners();
      return false;
    }
    try {
      final ok = await _ritimChannel.invokeMethod<bool>('exportMediaFile', {
        'path': path,
        'suggestedName': cleanExportFileNameFor(track),
        'mimeType': mimeTypeFor(track),
      });
      return ok == true;
    } catch (e) {
      statusBanner = 'Dosya kaydedilemedi: $e';
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    videoController?.removeListener(_onNativePlayerChanged);
    videoController?.dispose();
    super.dispose();
  }
}
