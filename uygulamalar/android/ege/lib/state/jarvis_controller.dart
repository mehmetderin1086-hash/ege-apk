import '../services/voice_project_catalog.dart';
import '../services/office_docs.dart';
import '../services/realtime_live_service.dart';
import '../services/speaker_identity.dart';

import 'dart:async';

import '../services/spreadsheet_spec.dart';
import '../services/document_spec.dart';
import '../services/google_workspace.dart';
import '../services/microsoft_workspace.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/jarvis_models.dart';
import '../models/pc_models.dart';
import '../services/agent_core.dart';
import '../services/evidence_memory.dart';
import '../services/obsidian_memory.dart';
import '../services/ai_client.dart';
import '../services/code_tools.dart';
import '../services/pc_bridge_client.dart';
import '../services/device_bridge.dart';
import '../services/local_command_engine.dart';
import '../services/local_whisper.dart';
import '../services/research_service.dart';
import '../services/storage_service.dart';
import '../services/voice_commands.dart';
import '../services/wake_word.dart';
import '../services/voice_service.dart';
import '../services/web_tools.dart';
import '../services/embedded_keys.dart';
import '../services/work_hub.dart';
import '../services/youtube_service.dart';

part 'jarvis_controller_features.dart';
part 'jarvis_controller_v3.dart';
part 'jarvis_controller_agent.dart';
part 'jarvis_controller_memory.dart';

enum LiveVoicePhase { idle, listening, thinking, speaking }

class JarvisController extends ChangeNotifier
    implements MobileStateDelegate, VoiceCommandHost {
  // ---- 4.0: Hermes ajanı
  final SkillStore skillStore = SkillStore();
  final EvidenceMemory evidenceMemory = EvidenceMemory();
  Map<String, dynamic> vaultStatus = {};
  String vaultMessage = '';
  Timer? _vaultDebounce;
  bool _vaultSyncing = false;
  bool _memoryLearning = false;
  final CronStore cronStore = CronStore();
  final Map<String, List<TodoItem>> todos = {};
  final List<ToolLogEntry> toolLog = [];
  final Set<String> runningCron = {};

  /// Oturum kimliği -> kayan özet (özetin kapsadığı son mesajın kimliği).
  final Map<String, ({String summary, String coveredUntilId})>
  compressionCache = {};

  /// Bağlam özetlenirken dolu ('Konuşma özetleniyor...'), aksi halde null.
  String? compressStatus;
  bool _compressionLoaded = false;

  /// PC terminalinde kullanıcı onayı bekleyen komut (sohbette onay kartı).
  ({String cmd, String? cwd, String reason})? pendingApproval;

  // ---- 3.0: asistan hareketi ekran görüntüsü, sohbet taslağı, uyandırma
  Uint8List? lastAssistScreenshot;
  DateTime? lastAssistScreenshotAt;

  /// Uygulama ön planda mı (uyandırma: pencere mi açılsın, ekransız mı).
  bool appInForeground = true;

  /// Paylaş / seçili metin gibi dış kaynaklardan gelen ve sohbet kutusuna
  /// yazılacak metin (ChatScreen tüketir).
  String? pendingDraft;
  bool _closingAssistant = false;
  bool wakeWordActive = false;
  String? wakeWordError;
  bool wakeWordStoppedByUser = false;

  @override
  Future<String> runDailyBriefing({bool speak = false}) =>
      speak ? briefingToChat(speak: true) : briefingText();

  @override
  Future<String> askAboutScreen(String question) => screenAnswer(question);

  @override
  Future<String> readNotifications() => readRecentNotifications();

  final StorageService _storage;
  final VoiceService _voice;
  final http.Client? httpClient;
  final ImagePicker _imagePicker = ImagePicker();

  JarvisController({
    StorageService? storage,
    VoiceService? voice,
    this.httpClient,
  }) : _storage = storage ?? StorageService(),
       _voice = voice ?? VoiceService();

  bool initialized = false;
  Future<List<DeviceAppInfo>>? _commandApps;
  final Stopwatch _commandAppsAge = Stopwatch();

  Future<List<DeviceAppInfo>> commandApps() {
    if (_commandApps == null || _commandAppsAge.elapsed >= const Duration(seconds: 15)) {
      _commandAppsAge..reset()..start();
      final loading = DeviceBridge.listInstalledApps();
      _commandApps = loading;
      loading.then((apps) {
        if (apps.isEmpty && identical(_commandApps, loading)) _commandApps = null;
      });
    }
    return _commandApps!;
  }
  final GoogleWorkspace googleWorkspace = GoogleWorkspace();
  final MicrosoftWorkspace microsoftWorkspace = MicrosoftWorkspace();
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  int mainTabIndex = 0;
  int toolsSubTabIndex = 0;

  JarvisSettings settings = const JarvisSettings();
  List<ChatSession> sessions = [];
  String activeSessionId = 'session-1';
  List<ChatAttachment> pendingAttachments = [];

  List<JarvisNote> notes = [];
  String activeNoteId = 'note-1';
  List<JarvisTimer> _timers = [];
  List<StudyArtifact> studies = [];
  DeviceMetrics deviceMetrics = const DeviceMetrics();

  bool isStreaming = false;
  String? speakingMessageId;
  bool isDictating = false;
  String dictationPreview = '';

  // Jarvis Live state
  LiveVoicePhase livePhase = LiveVoicePhase.idle;
  bool liveLoopActive = false;
  int _liveTurnGeneration = 0;
  Completer<Uint8List?>? _liveCapture;
  Completer<Uint8List?>? _duplexCapture;
  int _duplexToken = 0;
  bool _duplexInterrupted = false;

  Future<void> _startLiveDuplex(int generation) async {
    // Without a ready local model, keep the configured STT fallback usable.
    if (!_ownsLiveTurn(generation) || usableWhisperModel == null) return;
    final token = ++_duplexToken;
    final capture = Completer<Uint8List?>();
    _duplexCapture = capture;
    _duplexInterrupted = false;
    DeviceBridge.onDuplexEvent = (event) {
      if (!_ownsLiveTurn(generation) ||
          event['token'] != token ||
          !identical(_duplexCapture, capture)) {
        return;
      }
      switch (event['event']) {
        case 'candidate':
          final wav = event['wav'];
          if (wav is Uint8List) {
            unawaited(() async {
              final accepted = await SpeakerIdentity.instance.acceptsWav(wav);
              if (_ownsLiveTurn(generation) &&
                  identical(_duplexCapture, capture)) {
                await DeviceBridge.duplexSpeakerDecision(token, accepted);
              }
            }());
          }
        case 'speech':
          if (_duplexInterrupted) return;
          _duplexInterrupted = true;
          livePhase = LiveVoicePhase.listening;
          liveStatusHint = 'Seni dinliyorum...';
          // Capture continues with its pre-roll while playback is stopped.
          unawaited(_voice.stopSpeaking());
          notifyListeners();
        case 'level':
          if (livePhase == LiveVoicePhase.listening) {
            orbAmplitude = (event['level'] as num?)?.toDouble() ?? 0;
            notifyListeners();
          }
        case 'audio':
          if (!capture.isCompleted) {
            capture.complete(
              event['wav'] is Uint8List ? event['wav'] as Uint8List : null,
            );
          }
        case 'error':
          if (!capture.isCompleted) capture.complete(null);
      }
    };
    final status = await DeviceBridge.startDuplexCapture(
      token,
      settings.liveBargeIn,
    );
    if (!_ownsLiveTurn(generation)) return;
    if (status['status'] != 'OK') {
      _duplexCapture = null;
      DeviceBridge.onDuplexEvent = null;
      if (!capture.isCompleted) capture.complete(null);
    } else {
      liveStatusHint = status['bargeIn'] == true
          ? 'Konuşarak ya da dokunarak araya girebilirsin.'
          : 'Kesmek için dokun; ardından seni dinleyeceğim.';
      notifyListeners();
    }
  }

  Future<({bool available, bool permissionDenied, String text})>
  _finishDuplexTurn(int generation, Completer<Uint8List?> capture) async {
    final wav = await capture.future.timeout(
      const Duration(seconds: 35),
      onTimeout: () => null,
    );
    if (!_ownsLiveTurn(generation)) {
      return (available: true, permissionDenied: false, text: '');
    }
    _duplexCapture = null;
    DeviceBridge.onDuplexEvent = null;
    await DeviceBridge.stopDuplexCapture();
    if (wav == null || wav.length <= 44) {
      return (available: true, permissionDenied: false, text: '');
    }
    livePhase = LiveVoicePhase.thinking;
    liveStatusHint = 'Sesini çözümlüyorum...';
    notifyListeners();
    final result = await transcribeSpeech(wav);
    if (!_ownsLiveTurn(generation)) {
      return (available: true, permissionDenied: false, text: '');
    }
    liveTranscript = result.ok ? result.text.trim() : '';
    if (!result.ok) liveStatusHint = result.error ?? 'Ses çözümlenemedi';
    notifyListeners();
    return (available: true, permissionDenied: false, text: liveTranscript);
  }

  bool _ownsLiveTurn(int generation) =>
      liveLoopActive && generation == _liveTurnGeneration;

  void _invalidateLiveTurn() {
    _liveTurnGeneration++;
    final socket = _liveSocket;
    _liveSocket = null;
    if (socket != null) unawaited(socket.close());
    final duplex = _duplexCapture;
    _duplexCapture = null;
    DeviceBridge.onDuplexEvent = null;
    unawaited(DeviceBridge.stopDuplexCapture());
    if (duplex != null && !duplex.isCompleted) duplex.complete(null);
    if (_phoneLiveActive) {
      _phoneLiveActive = false;
      unawaited(DeviceBridge.cancelPhoneSpeech());
    }
    final capture = _liveCapture;
    _liveCapture = null;
    if (capture != null && !capture.isCompleted) capture.complete(null);
  }

  String liveTranscript = '';
  String liveAssistantReply = '';
  String liveStatusHint = 'Dokun ve konuşmaya başla';
  double orbAmplitude = 0.0;

  // Realtime Live session (Gemini Live / OpenAI Live) & WAV STT state
  bool _wavDictationActive = false;
  bool _phoneDictationActive = false;
  bool _phoneLiveActive = false;

  /// Android'in cihaz içi Türkçe tanıması bu çalıştırmada hata verdi
  /// (model kurulu değil vb.): sonraki turlar doğrudan kayıt + bulut
  /// çözümlemeye gider, her turda aynı hata ve indirme penceresi yinelenmez.
  bool _phoneSttDown = false;

  /// Ses kimliği filtresinin art arda reddettiği canlı tur sayısı.
  int _liveSpeakerRejects = 0;

  void _liveLog(String msg) => debugPrint('[Ege] canlı: $msg');

  /// Android'in cihaz içi Türkçe tanıması bu çalıştırmada kullanılamadı;
  /// konuşma bulutta (Gemini) çözülüyor. Arayüz uyarı gösterir.
  bool get phoneSttUnavailable => _phoneSttDown;

  /// Kullanıcı isteğiyle Android'in Türkçe model indirme penceresini açar.
  Future<void> requestPhoneSttModel() async {
    _liveLog('kullanıcı Türkçe modeli indirmeyi istedi');
    await DeviceBridge.preparePhoneSpeech(force: true);
  }

  static bool _phoneSttFailed(String status) =>
      status != 'OK' &&
      status != 'NO_SPEECH' &&
      status != 'CANCELLED' &&
      status != 'PERMISSION_NEEDED';
  int _dictationGeneration = 0;
  bool _dictationStarting = false;
  Timer? _dictationWatchdog;
  bool _pausedMusicForMic = false;
  bool _duckedMusicForMic = false;
  final List<String> _pendingLiveAnnouncements = [];

  /// Mikrofon açılmadan önce Ege'nin müziğini duraklatır (olmazsa kısar).
  Future<void> _pauseMusicForMic() async {
    if (_pausedMusicForMic || _duckedMusicForMic) return;
    if (!musicActive || musicState == 'paused') return;
    if (await DeviceBridge.streamPause()) {
      _pausedMusicForMic = true;
    } else {
      await DeviceBridge.streamDuck(true);
      _duckedMusicForMic = true;
    }
  }

  Future<void> _restoreMusicAfterMic() async {
    if (_pausedMusicForMic) {
      _pausedMusicForMic = false;
      await DeviceBridge.streamResume();
    }
    if (_duckedMusicForMic) {
      _duckedMusicForMic = false;
      await DeviceBridge.streamDuck(false);
    }
  }

  void _cancelDictationWatchdog() {
    _dictationWatchdog?.cancel();
    _dictationWatchdog = null;
  }

  static const String _micPermissionText =
      'Mikrofon izni gerekiyor. İzin penceresini onaylayıp tekrar dene.';

  // Device control state
  bool torchOn = false;
  int mediaVolumePct = 50;
  @override
  List<DeviceAppInfo> installedApps = const [];

  bool get isRealtimeActive => false;

  // ---- Windows-parity feature state (see jarvis_controller_features.dart)
  late final WorkHub works = WorkHub(
    settingsGetter: () => settings,
    httpClient: httpClient,
    downloadFileHandler: (url, {fileName}) =>
        downloadFile(url, fileName: fileName),
    downloadVideoHandler: downloadVideo,
    onFinished: _onWorkFinished,
  );
  YtVideo? musicNow;
  List<YtVideo> musicQueue = const [];
  int musicIndex = -1;
  Map<String, dynamic> musicStatus = const {};
  bool musicBusy = false;
  String? musicError;
  Timer? musicPoller;
  bool musicAdvancing = false;
  List<YtVideo> ytResults = const [];
  bool ytSearching = false;
  String ytQuery = '';
  String? ytError;
  Map<String, Map<String, dynamic>> profiles = const {};

  /// Screen requested by a voice command ('works' | 'youtube' | 'memory' |
  /// 'voices' | 'diagnostics'); HomeShell opens it and clears the field.
  String? pendingRoute;

  // ---- On-device Whisper model manager (see jarvis_controller_features.dart)
  Set<String> whisperDownloaded = const {};
  String? whisperDownloadingId;
  double whisperDownloadProgress = 0;
  int whisperDownloadedBytes = 0;
  String? whisperDownloadError;
  bool whisperCancelRequested = false;

  /// Engine + timing of the last transcription, e.g. "Yerel Whisper (Small) • 1.4 sn".
  String? lastSttInfo;

  void notifyChanged() => notifyListeners();

  void _onWorksChanged() => notifyListeners();

  Future<void> deliverWorkFiles(WorkJob job, String sessionId) async {
    final session = sessions.where((s) => s.id == sessionId).firstOrNull;
    if (session == null ||
        job.outputs.isEmpty ||
        session.messages.any((m) => m.id == 'file-${job.id}'))
      return;
    final message = JarvisMessage(
      id: 'file-${job.id}',
      role: 'assistant',
      content: 'Dosyan hazır. Aşağıdan açabilir veya paylaşabilirsin.',
      timestamp: DateTime.now(),
      attachments: [
        for (final file in job.outputs)
          ChatAttachment(
            id: '${job.id}-${file.name}',
            name: file.name,
            mimeType: file.mime,
            kind: 'file',
            localPath: file.path,
            publicUri: file.publicUri,
          ),
      ],
    );
    _replaceSession(
      session.copyWith(
        updatedAt: DateTime.now(),
        messages: [...session.messages, message],
      ),
    );
    await persistSessions();
    notifyListeners();
  }

  void _onWorkFinished(WorkJob j) {
    final ok = j.status == 'completed';
    if (j.status == 'cancelled') return;
    if (ok && j.chatSessionId != null)
      unawaited(deliverWorkFiles(j, j.chatSessionId!));
    unawaited(
      DeviceBridge.showNotification(
        title: ok ? '✅ İş tamamlandı' : '❌ İş başarısız',
        body:
            '${WorkKind.label(j.kind)}: ${j.title}${ok ? '' : ' — ${j.error}'}',
      ),
    );
    if (liveLoopActive) {
      // Canlı yanıtı kesme: duyuruyu sıraya al, tur arasında okunur.
      _pendingLiveAnnouncements.add(
        ok
            ? '${WorkKind.label(j.kind)} tamamlandı.'
            : '${WorkKind.label(j.kind)} başarısız oldu.',
      );
      liveStatusHint = ok
          ? 'Bir iş tamamlandı, sıradaki turda söyleyeceğim.'
          : 'Bir iş başarısız oldu, sıradaki turda söyleyeceğim.';
      notifyListeners();
    }
  }

  /// All speech input is recorded as WAV and transcribed by Whisper: on the
  /// phone (whisper.cpp + Hugging Face model) or via the OpenAI API.
  bool get usesWavCaptureStt => true;

  // Model discovery / connection test
  bool testingConnection = false;
  bool? connectionOk;
  String? connectionStatusMessage;
  List<ProxyModelInfo> proxyModels = ProxyModelInfo.fallbackCatalog;
  List<String> availableModels = ProxyModelInfo.fallbackCatalog
      .map((m) => m.id)
      .toList();

  ProxyModelInfo get activeModelInfo {
    for (final m in proxyModels) {
      if (m.id == settings.model) return m;
    }
    return ProxyModelInfo.classify(settings.model);
  }

  bool get isImageGenerationModel => activeModelInfo.category == 'image';

  List<ProxyModelInfo> get imageModels =>
      proxyModels.where((m) => m.category == 'image').toList();

  List<ProxyModelInfo> get chatModels =>
      proxyModels.where((m) => m.category == 'chat').toList();

  // Calculator history (in-memory convenience)
  final List<({String expr, String result})> calcHistory = [];

  Timer? _ticker;
  int nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  StreamSubscription<AiStreamEvent>? _activeStreamSub;
  Completer<void>? _streamCompleter;

  @override
  List<JarvisTimer> get timers => List.unmodifiable(_timers);

  List<JarvisTimer> get activeTimers =>
      _timers.where((t) => !t.fired && !t.acknowledged).toList();

  List<JarvisTimer> get firedUnacknowledgedTimers =>
      _timers.where((t) => t.fired && !t.acknowledged).toList();

  ChatSession get activeSession {
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    if (sessions.isNotEmpty) return sessions.first;
    final fallback = ChatSession(
      id: 'session-1',
      title: 'Ana Sohbet',
      updatedAt: DateTime.now(),
      messages: const [],
    );
    sessions = [fallback];
    activeSessionId = fallback.id;
    return fallback;
  }

  JarvisNote get activeNote {
    for (final n in notes) {
      if (n.id == activeNoteId) return n;
    }
    if (notes.isNotEmpty) return notes.first;
    final fallback = JarvisNote(
      id: 'note-1',
      title: 'Hızlı Notlar',
      content: '',
      updatedAt: DateTime.now(),
    );
    notes = [fallback];
    activeNoteId = fallback.id;
    return fallback;
  }

  Future<void> init({bool loadPlatformTelemetry = true}) async {
    if (initialized) return;

    final results = await Future.wait([
      _storage.loadSettings(),
      _storage.loadSessions(),
      _storage.loadNotes(),
      _storage.loadTimers(),
      _storage.loadStudies(),
      _storage.loadCachedModels(),
    ]);

    settings = results[0] as JarvisSettings;
    if (settings.sttMode != 'system') {
      settings = settings.copyWith(sttMode: 'system');
      await _storage.saveSettings(settings);
    }
    if (loadPlatformTelemetry && settings.sttMode == 'system') {
      unawaited(DeviceBridge.preparePhoneSpeech());
    }
    final embedded = EmbeddedKeys.instance;
    if (embedded.available &&
        settings.embeddedKeysVersion < EmbeddedKeys.version) {
      settings = embedded.applyTo(settings);
      await _storage.saveSettings(settings);
    }
    final sessionRes =
        results[1] as ({List<ChatSession> sessions, String activeId});
    sessions = sessionRes.sessions;
    activeSessionId = sessions.any((s) => s.id == sessionRes.activeId)
        ? sessionRes.activeId
        : sessions.first.id;
    notes = results[2] as List<JarvisNote>;
    if (notes.isNotEmpty) {
      activeNoteId = notes.first.id;
    }
    _timers = results[3] as List<JarvisTimer>;
    studies = results[4] as List<StudyArtifact>;
    proxyModels = results[5] as List<ProxyModelInfo>;
    _syncAvailableModelsList();

    nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _checkTimersTick(announce: false);
    await Future.wait([works.load(), loadProfiles(), initAgent(), evidenceMemory.load()]);
    works.addListener(_onWorksChanged);
    unawaited(refreshVaultStatus());
    scheduleVaultSync();

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      works.tick();
      nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _checkTimersTick(announce: true);
    });

    initialized = true;
    notifyListeners();

    if (loadPlatformTelemetry) {
      attachNativeEvents();
      unawaited(catchUpCron());
      unawaited(syncBriefingSchedule());
      if (settings.wakeWordEnabled) unawaited(startWakeWord());
      unawaited(refreshDeviceMetrics());
      unawaited(refreshProxyModels(silent: true));
      if (settings.pcPaired) unawaited(refreshPcInfo());
      unawaited(refreshWhisperModels(autoDownload: true));
    }
  }

  void _syncAvailableModelsList() {
    final merged = <String>{
      for (final m in proxyModels) m.id,
      if (settings.model.trim().isNotEmpty) settings.model.trim(),
    };
    availableModels = merged.toList();
  }

  @override
  void openTab(int mainTab, {int? toolsSubTab}) {
    mainTabIndex = mainTab.clamp(0, 5);
    if (toolsSubTab != null) {
      toolsSubTabIndex = toolsSubTab.clamp(0, 3);
    }
    notifyListeners();
  }

  // -------------------- DEVICE TELEMETRY --------------------

  Future<void> refreshDeviceMetrics() async {
    try {
      deviceMetrics = await DeviceBridge.getDeviceMetrics();
      final vol = await DeviceBridge.getVolumeState();
      final pctRaw = vol['mediaPct'] ?? vol['percent'];
      if (pctRaw is num) {
        mediaVolumePct = pctRaw.round().clamp(0, 100);
      }
      if (vol['torch'] is bool) {
        torchOn = vol['torch'] as bool;
      }
      if (installedApps.isEmpty) {
        installedApps = await DeviceBridge.listInstalledApps();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshInstalledApps() async {
    try {
      installedApps = await DeviceBridge.listInstalledApps();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> toggleFlashlight([bool? enabled]) async {
    final target = enabled ?? !torchOn;
    final ok = await DeviceBridge.setFlashlight(target);
    if (ok) {
      torchOn = target;
      notifyListeners();
    }
    return ok;
  }

  Future<void> setMediaVolume(int pct) async {
    final clamped = pct.clamp(0, 100);
    mediaVolumePct = clamped;
    notifyListeners();
    await DeviceBridge.setVolumeLevel(stream: 'media', percent: clamped);
  }

  Future<bool> controlMedia(String action) async {
    return DeviceBridge.controlMedia(action);
  }

  Future<bool> launchInstalledApp(String query) async {
    final launched = await DeviceBridge.launchApp(query);
    return launched != null && launched.isNotEmpty;
  }

  Future<bool> openSystemSettings(String target) async {
    return DeviceBridge.openSystemSettings(target);
  }

  Future<bool> setSystemAlarm(int hour, int minute, String msg) async {
    return DeviceBridge.setSystemAlarm(
      hour: hour,
      minute: minute,
      message: msg,
    );
  }

  // -------------------- SETTINGS & CONNECTION --------------------

  Future<void> updateSettings(JarvisSettings next) async {
    final prev = settings;
    settings = next;
    if (next.provider == ApiProvider.cliProxyApi) {
      proxyModels = ProxyModelInfo.mergeCatalog(proxyModels);
      _syncAvailableModelsList();
    }
    await _storage.saveSettings(next);
    scheduleVaultSync();
    notifyListeners();
    if (prev.briefingEnabled != next.briefingEnabled ||
        prev.briefingTime != next.briefingTime) {
      unawaited(syncBriefingSchedule());
    }
    if (prev.wakeWordEnabled != next.wakeWordEnabled ||
        (next.wakeWordEnabled &&
            prev.wakeWordSensitivity != next.wakeWordSensitivity)) {
      unawaited(() async {
        await stopWakeWord();
        if (next.wakeWordEnabled) await startWakeWord();
      }());
    }
  }

  Future<void> testConnection() => refreshProxyModels(silent: false);

  Future<void> refreshProxyModels({bool silent = false}) async {
    if (!silent) {
      testingConnection = true;
      connectionStatusMessage = null;
      notifyListeners();
    }

    final res = await AiClient.testAndFetchModels(settings, client: httpClient);
    if (!silent) {
      testingConnection = false;
    }
    connectionOk = res.ok;
    if (res.ok || !silent) {
      connectionStatusMessage = res.message;
    }
    if (res.detailedModels.isNotEmpty) {
      proxyModels = settings.provider == ApiProvider.cliProxyApi
          ? ProxyModelInfo.mergeCatalog(res.detailedModels)
          : ProxyModelInfo.mergeCatalog(
              res.detailedModels,
              ProxyModelInfo.fallbackCatalog,
            );
      _syncAvailableModelsList();
      await _storage.saveCachedModels(proxyModels);
      final chatList = chatModels;
      final hasCurrent = proxyModels.any((m) => m.id == settings.model);
      if (res.ok && !hasCurrent && chatList.isNotEmpty) {
        final preferred = chatList.firstWhere(
          (m) => m.id == 'gemini-4-hydrogen',
          orElse: () => chatList.firstWhere(
            (m) => m.id == 'gemini-2.5-flash',
            orElse: () => chatList.first,
          ),
        );
        await updateSettings(settings.copyWith(model: preferred.id));
        connectionStatusMessage =
            'Seçili model bulunamadı, ${preferred.id} seçildi';
      }
    } else if (settings.provider == ApiProvider.cliProxyApi) {
      proxyModels = ProxyModelInfo.mergeCatalog(proxyModels);
      _syncAvailableModelsList();
    }
    notifyListeners();
  }

  Future<String> selectModel(ProxyModelInfo modelInfo) async {
    if (modelInfo.category == 'tts') {
      await updateSettings(settings.copyWith(useProxyTts: true));
      return 'Proxy TTS etkinleştirildi (${modelInfo.id}).';
    }
    if (modelInfo.category != 'chat') {
      return 'Bu model sohbet için uygun değil.';
    }
    var next = settings.copyWith(model: modelInfo.id);
    if (settings.provider == ApiProvider.geminiDirect &&
        modelInfo.familyLabel != 'Gemini') {
      final pUrl = settings.ttsProxyUrl.trim();
      final pKey = settings.ttsProxyKey.trim();
      if (pUrl.isNotEmpty && pKey.isNotEmpty && pKey != 'sk-local') {
        next = next.copyWith(
          provider: ApiProvider.cliProxyApi,
          baseUrl: pUrl,
          apiKey: pKey,
        );
      }
    }
    await updateSettings(next);
    return 'Aktif model değiştirildi: ${modelInfo.id}';
  }

  Future<String> testVoice() async {
    await _voice.speak(
      'Merhaba, ben Ege. Bulut ses sistemim aktif ve hazır.',
      rate: settings.ttsRate,
      pitch: settings.ttsPitch,
      settings: settings,
      httpClient: httpClient,
    );
    notifyListeners();
    return _voice.lastEngineUsed;
  }

  /// Name of the engine that produced the last spoken reply.
  String get lastTtsEngine => _voice.lastEngineUsed;

  List<TtsAttempt> get lastTtsAttempts => _voice.lastAttempts;

  Future<List<TtsAttempt>> diagnoseTts() =>
      AiClient.diagnoseTts(settings: settings, client: httpClient);

  // -------------------- CLOUD VOICE STUDIO --------------------

  String? previewingVoiceId;
  List<JarvisVoiceOption> azureCloudVoices = const [];
  bool loadingAzureVoices = false;

  JarvisSettings _settingsForVoice(JarvisVoiceOption v) {
    var next = settings.copyWith(proxyTtsVoice: v.id, useProxyTts: true);
    if (v.engine == 'edge') {
      next = next.copyWith(ttsEngine: 'edge_neural');
    } else if (next.ttsEngine != 'proxy') {
      next = next.copyWith(ttsEngine: 'auto');
    }
    return next;
  }

  Future<String> previewVoice(JarvisVoiceOption v, {String? text}) async {
    previewingVoiceId = v.id;
    notifyListeners();
    try {
      await _voice.speak(
        text ??
            'Merhaba, ben Ege. ${v.shortName} sesiyle konuşuyorum. '
                'Bugün sana nasıl yardımcı olabilirim?',
        rate: settings.ttsRate,
        pitch: settings.ttsPitch,
        settings: _settingsForVoice(v),
        httpClient: httpClient,
      );
      return _voice.lastEngineUsed;
    } finally {
      previewingVoiceId = null;
      notifyListeners();
    }
  }

  Future<void> selectVoice(JarvisVoiceOption v) =>
      updateSettings(_settingsForVoice(v));

  Future<String?> loadAzureCloudVoices() async {
    loadingAzureVoices = true;
    notifyListeners();
    final r = await AiClient.fetchAzureVoices(settings, client: httpClient);
    azureCloudVoices = r.voices;
    loadingAzureVoices = false;
    notifyListeners();
    return r.error;
  }

  // -------------------- PC BRIDGE (Windows) --------------------

  PcHostInfo? pcInfo;
  bool? pcOnline;
  String? pcStatus;
  bool pcScanning = false;
  double pcScanProgress = 0;
  List<PcDiscovered> pcFound = const [];
  PcKeyBundle? lastImportedBundle;
  double? apkDownloadProgress;

  PcBridgeClient? get pcClient => settings.pcPaired
      ? PcBridgeClient(
          baseUrl: settings.pcBridgeUrl,
          token: settings.pcBridgeToken,
          client: httpClient,
        )
      : null;

  Future<void> discoverPcs() async {
    if (pcScanning) return;
    pcScanning = true;
    pcScanProgress = 0;
    pcFound = const [];
    notifyListeners();
    try {
      final extra = <String>[];
      final last = Uri.tryParse(
        PcBridgeClient.normalizeUrl(settings.pcBridgeUrl),
      );
      if (last != null && last.host.isNotEmpty) extra.add(last.host);
      var lastNotify = 0.0;
      pcFound = await PcBridgeClient.discover(
        extraHosts: extra,
        onProgress: (p) {
          pcScanProgress = p;
          if (p - lastNotify > 0.05 || p >= 1) {
            lastNotify = p;
            notifyListeners();
          }
        },
      );
    } finally {
      pcScanning = false;
      notifyListeners();
    }
  }

  /// Pairs with the PC using its 6-digit PIN, then imports the CLI Proxy API
  /// keys automatically. Returns an error message or null on success.
  Future<String?> pairPc(String url, String pin) async {
    try {
      final norm = PcBridgeClient.normalizeUrl(url);
      final device = '${deviceMetrics.manufacturer} ${deviceMetrics.model}'
          .trim();
      final res = await PcBridgeClient.pair(
        norm,
        pin,
        device: device.isEmpty ? 'Ege Android' : device,
        client: httpClient,
      );
      await updateSettings(
        settings.copyWith(
          pcBridgeUrl: norm,
          pcBridgeToken: res.token,
          pcBridgeName: res.host,
        ),
      );
      await refreshPcInfo();
      return null;
    } on PcBridgeException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<void> refreshPcInfo() async {
    final c = pcClient;
    if (c == null) {
      pcInfo = null;
      pcOnline = null;
      notifyListeners();
      return;
    }
    try {
      pcInfo = await c.info();
      pcOnline = true;
      pcStatus = null;
    } on PcBridgeException catch (e) {
      pcOnline = false;
      pcStatus = e.unauthorized
          ? 'PC eşleşmeyi tanımıyor. Yeniden eşleşin.'
          : e.message;
    } catch (e) {
      pcOnline = false;
      pcStatus = '$e';
    }
    notifyListeners();
  }

  Future<void> unpairPc() async {
    try {
      await pcClient?.unpair();
    } catch (_) {}
    await updateSettings(
      settings.copyWith(pcBridgeToken: '', pcBridgeName: ''),
    );
    pcInfo = null;
    pcOnline = null;
    pcStatus = null;
    notifyListeners();
  }

  /// Pulls every API key found in the PC's CLI Proxy API environment and
  /// wires them into chat + cloud voices.
  Future<({bool ok, String message, List<String> items})> importKeysFromPc({
    bool switchChatToProxy = true,
  }) async {
    final c = pcClient;
    if (c == null) {
      return (
        ok: false,
        message: 'Önce PC ile eşleşin.',
        items: const <String>[],
      );
    }
    try {
      final b = await c.keys();
      var next = settings;
      if (b.proxyBaseUrl.isNotEmpty) {
        next = next.copyWith(
          ttsProxyUrl: b.proxyBaseUrl,
          ttsProxyKey: b.proxyApiKey,
        );
        if (switchChatToProxy && b.proxyReachable) {
          next = next.copyWith(
            provider: ApiProvider.cliProxyApi,
            baseUrl: b.proxyBaseUrl,
            apiKey: b.proxyApiKey.isNotEmpty ? b.proxyApiKey : next.apiKey,
          );
        }
      }
      if (b.azureKey.isNotEmpty) {
        next = next.copyWith(
          azureSpeechKey: b.azureKey,
          azureSpeechRegion: b.azureRegion,
        );
      }
      if (b.geminiKey.isNotEmpty) {
        next = next.copyWith(geminiTtsKey: b.geminiKey);
      }
      if (b.googleCloudKey.isNotEmpty) {
        next = next.copyWith(googleCloudTtsKey: b.googleCloudKey);
      }
      if (b.openAiKey.isNotEmpty) {
        next = next.copyWith(
          openAiTtsKey: b.openAiKey,
          openAiLiveKey: next.openAiLiveKey.trim().isEmpty ? b.openAiKey : null,
        );
      }
      if (next.ttsEngine == 'device') next = next.copyWith(ttsEngine: 'auto');
      next = next.copyWith(useProxyTts: true);
      await updateSettings(next);
      lastImportedBundle = b;
      await refreshProxyModels(silent: true);
      final items = b.summary;
      return (
        ok: items.isNotEmpty,
        message: items.isEmpty
            ? 'PC\'de CLI Proxy API anahtarı bulunamadı.'
            : '${items.length} API PC\'den alındı ve etkinleştirildi.',
        items: items,
      );
    } on PcBridgeException catch (e) {
      return (ok: false, message: e.message, items: const <String>[]);
    } catch (e) {
      return (ok: false, message: '$e', items: const <String>[]);
    }
  }

  /// Downloads the newest APK built on the PC and opens Android's installer.
  Future<String> updateAppFromPc() async {
    final c = pcClient;
    if (c == null) return 'Önce PC ile eşleşin.';
    apkDownloadProgress = 0;
    notifyListeners();
    var last = 0.0;
    try {
      final bytes = await c.downloadApk(
        onProgress: (r, t) {
          if (t <= 0) return;
          final p = r / t;
          if (p - last >= 0.02 || p >= 1) {
            last = p;
            apkDownloadProgress = p;
            notifyListeners();
          }
        },
      );
      final res = await DeviceBridge.installApk(bytes);
      return res;
    } on PcBridgeException catch (e) {
      return e.message;
    } catch (e) {
      return 'APK indirilemedi: $e';
    } finally {
      apkDownloadProgress = null;
      notifyListeners();
    }
  }

  static const String _codeEditSystem = '''
Sen kıdemli bir yazılım mühendisi ve titiz bir kod editörüsün.
Sana bir dosyanın TAM içeriği ve bir değişiklik talimatı verilecek.
Kurallar:
1. Önce en fazla 3 kısa maddeyle Türkçe olarak ne değiştirdiğini yaz.
2. Ardından dosyanın GÜNCELLENMİŞ TAM İÇERİĞİNİ tek bir kod bloğu içinde ver.
3. Asla "...", "// değişmedi" veya benzeri kısaltma kullanma; dosyanın tamamını yaz.
4. Talimat dışındaki kodu, biçimlendirmeyi ve yorumları koru.
5. Derlenebilir, çalışır ve projenin mevcut stiline uygun kod yaz.''';

  /// Asks the active AI model to rewrite a PC file according to [instruction].
  Future<({bool ok, String code, String summary, String? error})> aiEditCode({
    required String path,
    required String content,
    required String instruction,
  }) async {
    if (content.length > 160000) {
      return (
        ok: false,
        code: '',
        summary: '',
        error: 'Dosya AI ile tam düzenleme için çok büyük (160 KB üstü).',
      );
    }
    final lang = CodeLang.detect(path);
    final user =
        'Dosya yolu: $path\nDil: ${CodeLang.label(lang)}\n\n'
        'Talimat:\n${instruction.trim()}\n\n'
        'Dosyanın mevcut tam içeriği:\n```$lang\n$content\n```';
    final res = await AiClient.completeOnce(
      settings: settings,
      system: _codeEditSystem,
      user: user,
      client: httpClient,
    );
    if (!res.ok) {
      return (
        ok: false,
        code: '',
        summary: '',
        error: res.error ?? 'AI yanıt vermedi.',
      );
    }
    final code = CodeAiParser.extractCode(res.text);
    if (code.trim().isEmpty) {
      return (
        ok: false,
        code: '',
        summary: '',
        error: 'AI kod bloğu döndürmedi.',
      );
    }
    return (
      ok: true,
      code: code,
      summary: CodeAiParser.extractSummary(res.text),
      error: null,
    );
  }

  /// Opens the chat tab and asks the assistant about a PC file.
  Future<void> sendCodeToChat({
    required String path,
    required String content,
    required String prompt,
  }) async {
    final name = path.split(RegExp(r'[\\/]')).last;
    final clipped = content.length > 60000
        ? '${content.substring(0, 60000)}\n… (dosyanın kalanı kırpıldı)'
        : content;
    addAttachment(
      ChatAttachment(
        id: LocalCommandEngine.newId(),
        name: name,
        mimeType: 'text/plain',
        kind: 'text',
        textContent: '// PC yolu: $path\n$clipped',
      ),
    );
    openTab(0);
    await sendMessage(prompt);
  }

  // -------------------- TIMERS --------------------

  Future<void> _checkTimersTick({required bool announce}) async {
    var changed = false;
    final newlyFired = <JarvisTimer>[];
    for (var i = 0; i < _timers.length; i++) {
      final t = _timers[i];
      if (!t.fired && nowEpoch >= t.fireAtEpoch) {
        final updated = t.copyWith(fired: true);
        _timers[i] = updated;
        newlyFired.add(updated);
        changed = true;
      }
    }

    if (changed) {
      await _storage.saveTimers(_timers);
    }

    if (announce && newlyFired.isNotEmpty) {
      if (Platform.isAndroid) {
        for (final timer in newlyFired) {
          await DeviceBridge.deliverDueTimer(timer.id);
        }
        notifyListeners();
        return;
      }
      // Masaüstünde bildirimi uygulama verir.
      for (final t in newlyFired) {
        unawaited(DeviceBridge.cancelAlarm(t.id));
      }
      unawaited(DeviceBridge.playTimerChime());
      final labels = newlyFired.map((e) => e.label).join(', ');
      unawaited(
        DeviceBridge.showNotification(
          title: 'Ege Zamanlayıcı',
          body: '$labels zamanlayıcısı doldu!',
        ),
      );
      if (!liveLoopActive && !_voice.isSpeaking) {
        unawaited(
          _voice.speak(
            'Dikkat! $labels zamanlayıcısı doldu.',
            rate: settings.ttsRate,
            pitch: settings.ttsPitch,
            settings: settings,
            httpClient: httpClient,
          ),
        );
      }
    }

    if (changed || activeTimers.isNotEmpty) {
      notifyListeners();
    }
  }

  @override
  Future<JarvisTimer> addTimer(int seconds, String label) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final clamped = seconds.clamp(1, 604800);
    final t = JarvisTimer(
      id: LocalCommandEngine.newId(),
      label: label.trim().isEmpty ? 'Sayaç' : label.trim(),
      durationSec: clamped,
      createdAtEpoch: now,
      fireAtEpoch: now + clamped,
    );
    _timers.insert(0, t);
    await _storage.saveTimers(_timers);
    nowEpoch = now;
    notifyListeners();
    // Also fires as a notification when Ege is closed.
    unawaited(
      DeviceBridge.scheduleAlarm(
        key: t.id,
        at: DateTime.fromMillisecondsSinceEpoch(t.fireAtEpoch * 1000),
        title: 'Ege • ${t.label}',
        body: '${t.label} zamanlayıcısının süresi doldu.',
      ),
    );
    return t;
  }

  @override
  Future<int> cancelTimers({bool all = false, bool earliest = false}) async {
    if (_timers.isEmpty) return 0;
    var removed = 0;
    if (all) {
      removed = _timers.length;
      for (final t in _timers) {
        unawaited(DeviceBridge.cancelAlarm(t.id));
      }
      _timers.clear();
    } else if (earliest) {
      final candidates = _timers.where((t) => !t.fired).toList()
        ..sort((a, b) => a.fireAtEpoch.compareTo(b.fireAtEpoch));
      if (candidates.isNotEmpty) {
        final id = candidates.first.id;
        unawaited(DeviceBridge.cancelAlarm(id));
        _timers.removeWhere((t) => t.id == id);
        removed = 1;
      } else if (_timers.isNotEmpty) {
        _timers.removeAt(0);
        removed = 1;
      }
    } else {
      // Varsayılan: en son oluşturulan, henüz çalmamış zamanlayıcı.
      JarvisTimer? latest;
      for (final t in _timers) {
        if (t.fired) continue;
        if (latest == null || t.createdAtEpoch > latest.createdAtEpoch) {
          latest = t;
        }
      }
      if (latest != null) {
        final id = latest.id;
        unawaited(DeviceBridge.cancelAlarm(id));
        _timers.removeWhere((t) => t.id == id);
        removed = 1;
      }
    }
    if (removed > 0) {
      await _storage.saveTimers(_timers);
      notifyListeners();
    }
    return removed;
  }

  Future<void> removeTimerById(String id) async {
    unawaited(DeviceBridge.cancelAlarm(id));
    _timers.removeWhere((t) => t.id == id);
    await _storage.saveTimers(_timers);
    notifyListeners();
  }

  Future<void> acknowledgeTimer(String id) async {
    final idx = _timers.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _timers[idx] = _timers[idx].copyWith(acknowledged: true);
      await _storage.saveTimers(_timers);
      notifyListeners();
    }
  }

  Future<void> acknowledgeAllFired() async {
    var changed = false;
    for (var i = 0; i < _timers.length; i++) {
      if (_timers[i].fired && !_timers[i].acknowledged) {
        _timers[i] = _timers[i].copyWith(acknowledged: true);
        changed = true;
      }
    }
    if (changed) {
      await _storage.saveTimers(_timers);
      notifyListeners();
    }
  }

  // -------------------- NOTES --------------------

  @override
  Future<void> appendToActiveNote(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final current = activeNote;
    final sep = current.content.trim().isEmpty ? '' : '\n';
    final next = current.copyWith(
      content: '${current.content.trimRight()}$sep- $clean',
      updatedAt: DateTime.now(),
    );
    _replaceNote(next);
    await _storage.saveNotes(notes);
    notifyListeners();
  }

  Future<void> selectNote(String id) async {
    activeNoteId = id;
    notifyListeners();
  }

  Future<JarvisNote> createNote({String title = 'Yeni Not'}) async {
    final note = JarvisNote(
      id: LocalCommandEngine.newId(),
      title: title,
      content: '',
      updatedAt: DateTime.now(),
    );
    notes.insert(0, note);
    activeNoteId = note.id;
    await _storage.saveNotes(notes);
    notifyListeners();
    return note;
  }

  Future<void> updateActiveNote({String? title, String? content}) async {
    final current = activeNote;
    final next = current.copyWith(
      title: title ?? current.title,
      content: content ?? current.content,
      updatedAt: DateTime.now(),
    );
    _replaceNote(next);
    await _storage.saveNotes(notes);
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    notes.removeWhere((n) => n.id == id);
    if (notes.isEmpty) {
      notes.add(
        JarvisNote(
          id: LocalCommandEngine.newId(),
          title: 'Hızlı Notlar',
          content: '',
          updatedAt: DateTime.now(),
        ),
      );
    }
    activeNoteId = notes.first.id;
    await _storage.saveNotes(notes);
    notifyListeners();
  }

  void _replaceNote(JarvisNote updated) {
    final idx = notes.indexWhere((n) => n.id == updated.id);
    if (idx != -1) {
      notes[idx] = updated;
    } else {
      notes.insert(0, updated);
    }
  }

  Future<({bool ok, String text})> summarizeActiveNoteWithAi() async {
    final note = activeNote;
    if (note.content.trim().isEmpty) {
      return (ok: false, text: 'Özetlemek için not içeriği boş.');
    }
    final prompt =
        'Aşağıdaki mobil notu Türkçe olarak kısa maddeler, önemli noktalar ve varsa yapılacak aksiyonlar şeklinde özetle:\n\nBaşlık: ${note.title}\n\n${note.content}';
    final reply = await _runOneShotAi(prompt);
    return reply;
  }

  // -------------------- SESSIONS --------------------

  void selectSession(String id) {
    if (sessions.any((s) => s.id == id)) {
      activeSessionId = id;
      unawaited(persistSessions());
      notifyListeners();
    }
  }

  Future<ChatSession> createNewSession({String title = 'Yeni Sohbet'}) async {
    final session = ChatSession(
      id: LocalCommandEngine.newId(),
      title: title,
      updatedAt: DateTime.now(),
      messages: const [],
    );
    sessions.insert(0, session);
    activeSessionId = session.id;
    await persistSessions();
    notifyListeners();
    return session;
  }

  Future<void> renameSession(String id, String nextTitle) async {
    final clean = nextTitle.trim();
    if (clean.isEmpty) return;
    final idx = sessions.indexWhere((s) => s.id == id);
    if (idx != -1) {
      sessions[idx] = sessions[idx].copyWith(
        title: clean,
        updatedAt: DateTime.now(),
      );
      await persistSessions();
      notifyListeners();
    }
  }

  Future<void> deleteSession(String id) async {
    sessions.removeWhere((s) => s.id == id);
    if (sessions.isEmpty) {
      sessions.add(
        ChatSession(
          id: LocalCommandEngine.newId(),
          title: 'Ana Sohbet',
          updatedAt: DateTime.now(),
          messages: const [],
        ),
      );
    }
    if (!sessions.any((s) => s.id == activeSessionId)) {
      activeSessionId = sessions.first.id;
    }
    await persistSessions();
    notifyListeners();
  }

  Future<void> clearActiveSession() async {
    final current = activeSession;
    _replaceSession(
      current.copyWith(messages: const [], updatedAt: DateTime.now()),
    );
    await persistSessions();
    notifyListeners();
  }

  String exportSessionMarkdown(ChatSession session) {
    final buf = StringBuffer('# ${session.title}\n\n');
    for (final m in session.messages) {
      final who = m.role == 'user' ? 'Kullanıcı' : 'Ege';
      buf.writeln('## $who (${m.timestamp.toLocal()})');
      if (m.attachments.isNotEmpty) {
        buf.writeln(
          '_Ekler: ${m.attachments.map((a) => a.name).join(', ')}_\n',
        );
      }
      buf.writeln(m.content);
      buf.writeln();
    }
    return buf.toString();
  }

  Future<void> shareSession(ChatSession session) async {
    final md = exportSessionMarkdown(session);
    await SharePlus.instance.share(
      ShareParams(text: md, title: 'Ege - ${session.title}'),
    );
  }

  /// Uzun işlerin çıktısını, işi başlatan oturuma ekler (oturum silindiyse
  /// etkin oturuma düşer) ve kaydeder.
  Future<void> _appendToSession(String sid, JarvisMessage msg) async {
    final idx = sessions.indexWhere((s) => s.id == sid);
    final base = idx != -1 ? sessions[idx] : activeSession;
    _replaceSession(
      base.copyWith(
        updatedAt: DateTime.now(),
        messages: [...base.messages, msg],
      ),
    );
    await persistSessions();
    notifyChanged();
  }

  /// Test/entegrasyon için: _appendToSession'ın herkese açık sarmalayıcısı.
  Future<void> appendToSessionForTest(String sid, JarvisMessage msg) =>
      _appendToSession(sid, msg);

  void _replaceSession(ChatSession updated) {
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      sessions[idx] = updated;
    } else {
      sessions.insert(0, updated);
    }
  }

  // -------------------- ATTACHMENTS --------------------

  void addAttachment(ChatAttachment attachment) {
    pendingAttachments = [...pendingAttachments, attachment];
    notifyListeners();
  }

  void removeAttachment(String id) {
    pendingAttachments = pendingAttachments.where((a) => a.id != id).toList();
    notifyListeners();
  }

  void clearPendingAttachments() {
    if (pendingAttachments.isEmpty) return;
    pendingAttachments = [];
    notifyListeners();
  }

  Future<String?> pickImage({required ImageSource source}) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      final lower = file.name.toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg';
      addAttachment(
        ChatAttachment(
          id: LocalCommandEngine.newId(),
          name: file.name,
          mimeType: mime,
          kind: 'image',
          base64Data: base64Encode(bytes),
        ),
      );
      return null;
    } catch (e) {
      return 'Görsel alınamadı: $e';
    }
  }

  Future<String?> pickTextFile() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'txt',
          'md',
          'json',
          'csv',
          'log',
          'yaml',
          'yml',
          'xml',
          'py',
          'dart',
          'js',
          'ts',
        ],
      );
      if (picked.isEmpty) return null;
      if (picked.length > 8) return 'Bir seferde en fazla sekiz dosya seçebilirsin.';
      final additions = <ChatAttachment>[];
      for (final file in picked) {
        if ((await file.length() ?? 1048577) > 1048576) return '${file.name} 1 MB sınırını aşıyor.';
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) return '${file.name} boş.';
        var decoded = utf8.decode(bytes, allowMalformed: true);
        if (decoded.length > 24000) {
          decoded = '${decoded.substring(0, 24000)}\n... [kısaltıldı]';
        }
        additions.add(ChatAttachment(
          id: LocalCommandEngine.newId(),
          name: file.name,
          mimeType: 'text/plain',
          kind: 'text',
          textContent: decoded,
        ));
      }
      pendingAttachments = [...pendingAttachments, ...additions];
      notifyListeners();
      return null;
    } catch (e) {
      return 'Dosya seçilemedi: $e';
    }
  }

  // -------------------- CHAT & STREAMING --------------------

  final _pendingSends = <String, Future<void>>{};

  Future<void> sendMessage(String rawText, {bool speakReply = false}) {
    final key = jsonEncode([activeSessionId, rawText.trim(), pendingAttachments.map((a) => a.id).toList()]);
    return _pendingSends.putIfAbsent(key, () =>
      _sendMessageOnce(rawText, speakReply: speakReply).whenComplete(() { _pendingSends.remove(key); }));
  }

  Future<void> _sendMessageOnce(String rawText, {required bool speakReply}) async {
    final trimmed = rawText.trim();
    if (pendingAttachments.isEmpty && LocalCommandEngine.isAssistantExit(trimmed)) {
      await closeAssistant();
      return;
    }
    if (trimmed.startsWith('/') &&
        pendingAttachments.isEmpty &&
        !trimmed.startsWith('//')) {
      final reply = await handleSlashCommand(trimmed);
      if (reply != null) {
        if (reply != '__handled__') {
          final now = DateTime.now();
          _replaceSession(
            activeSession.copyWith(
              updatedAt: now,
              messages: [
                ...activeSession.messages,
                JarvisMessage(
                  id: LocalCommandEngine.newId(),
                  role: 'user',
                  content: trimmed,
                  timestamp: now,
                ),
                JarvisMessage(
                  id: LocalCommandEngine.newId(),
                  role: 'assistant',
                  content: reply,
                  timestamp: now,
                  modelUsed: 'Ege komutu',
                ),
              ],
            ),
          );
          await persistSessions();
          notifyListeners();
        }
        return;
      }
    }
    if (trimmed.isEmpty && pendingAttachments.isEmpty) return;

    if (isStreaming) {
      await stopStreaming();
    }

    final current = activeSession;
    final userMsg = JarvisMessage(
      id: LocalCommandEngine.newId(),
      role: 'user',
      content: trimmed.isEmpty ? 'Ekli içeriği analiz et.' : trimmed,
      timestamp: DateTime.now(),
      attachments: List<ChatAttachment>.from(pendingAttachments),
    );
    pendingAttachments = [];

    var nextTitle = current.title;
    if (current.messages.isEmpty &&
        (nextTitle == 'Ana Sohbet' || nextTitle == 'Yeni Sohbet') &&
        trimmed.isNotEmpty) {
      nextTitle = trimmed.length > 34
          ? '${trimmed.substring(0, 34)}...'
          : trimmed;
    }

    final withUser = current.copyWith(
      title: nextTitle,
      updatedAt: DateTime.now(),
      messages: [...current.messages, userMsg],
    );
    _replaceSession(withUser);
    await persistSessions();
    unawaited(learnPreferences(userMsg, current.id));
    notifyListeners();

    // Try offline LocalCommandEngine when no files/images attached
    if (userMsg.attachments.isEmpty) {
      final outcome = await runLocalCommand(trimmed);
      if (outcome != null && outcome.handled) {
        final assistantMsg = JarvisMessage(
          id: LocalCommandEngine.newId(),
          role: 'assistant',
          content: outcome.reply,
          timestamp: DateTime.now(),
          modelUsed: 'Yerel Motor (Çevrimdışı)',
          actionBanner: outcome.actionBanner,
        );
        final origin = sessions.firstWhere(
          (s) => s.id == current.id,
          orElse: () => withUser,
        );
        final updated = origin.copyWith(
          updatedAt: DateTime.now(),
          messages: [...origin.messages, assistantMsg],
        );
        _replaceSession(updated);
        await persistSessions();

        if (outcome.switchTabIndex != null) {
          openTab(
            outcome.switchTabIndex!,
            toolsSubTab: outcome.switchToolsSubTab,
          );
        } else {
          notifyListeners();
        }

        if (!liveLoopActive && (speakReply || settings.autoTts)) {
          await speakMessage(assistantMsg.id, assistantMsg.content);
        }
        return;
      }
    }

    // If active model is an image generation model, route straight to image generation
    if (isImageGenerationModel) {
      await _generateImageInChat(userMsg.content);
      return;
    }

    // Stream from AI provider (with automatic web page context for URLs)
    var history = await maybeCompress(withUser.messages);
    final urlContext = await _buildUrlContext(userMsg.content);
    final clipContext = await _clipboardContext(userMsg.content);
    final extraContext = [
      urlContext,
      clipContext,
      if (settings.memoryEnabled)
        await recallContext(userMsg.content, current.id, userMsg.id),
    ].where((e) => e.isNotEmpty).join('\n\n');
    if (extraContext.isNotEmpty) {
      history = [
        ...history.sublist(0, history.length - 1),
        userMsg.copyWith(content: '${userMsg.content}\n\n$extraContext'),
      ];
    }
    final turnStart = DateTime.now();
    // Keep the request alive while its phone tools switch to external apps.
    await keepAlive('agent', true, text: 'İsteğin üzerinde çalışıyorum');
    try {
      await _streamAiReply(
        history: history,
        speakReply: speakReply,
        sessionId: current.id,
      );
    } finally {
      await keepAlive('agent', false);
    }
    // Hermes öğrenme döngüsü: en az 2 araç kullanılan işlerden sonra.
    final used = toolLog
        .where((t) => t.at.isAfter(turnStart))
        .map((t) => t.tool)
        .toList();
    if (used.length >= 2 && !used.contains('skill_manage')) {
      final last = activeSession.messages.lastWhere(
        (m) => m.role == 'assistant',
        orElse: () => userMsg,
      );
      unawaited(
        learningCheck(
          request: userMsg.content,
          outcome: last.content,
          tools: used,
        ),
      );
    }
  }

  static const Set<String> _dataToolTypes = {
    ...JarvisAgent.agentToolTypes,
    'web_search',
    'fetch_url',
    'wikipedia',
    'weather',
    'currency',
    'news',
    'location',
    'list_apps',
    'app_usage',
  };

  Future<void> _streamAiReply({
    required List<JarvisMessage> history,
    required bool speakReply,
    int depth = 0,
    Set<String>? reminderActions,
    bool phoneTask = false,
    String? sessionId,
  }) async {
    final seenReminders = reminderActions ?? <String>{};
    final originId = sessionId ?? activeSessionId;
    final origin = sessions.where((s) => s.id == originId).firstOrNull;
    if (origin == null) return;
    final assistantId = LocalCommandEngine.newId();
    final placeholder = JarvisMessage(
      id: assistantId,
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      modelUsed: settings.model,
    );

    final withPlaceholder = origin.copyWith(
      updatedAt: DateTime.now(),
      messages: [...origin.messages, placeholder],
    );
    _replaceSession(withPlaceholder);

    isStreaming = true;
    notifyListeners();

    final sw = Stopwatch()..start();
    final completer = Completer<void>();
    _streamCompleter = completer;

    var finalReply = '';
    var hadError = false;
    List<Map<String, dynamic>> pendingDataTools = const [];
    final phoneActs = <Map<String, dynamic>>[];
    var doneBanners = <String>[];

    _activeStreamSub =
        AiClient.streamChat(
          settings: settings,
          messages: history,
          client: httpClient,
        ).timeout(const Duration(seconds: 90), onTimeout: (sink) {
          sink.addError(TimeoutException('Sunucudan 90 saniye boyunca yanıt gelmedi.'));
          sink.close();
        }).listen(
          (event) async {
            if (_streamCompleter != completer) return;
            if (event.error != null) {
              hadError = true;
              final errText = event.error!;
              _updateMessageInActiveSession(
                assistantId,
                (m) => m.copyWith(
                  content: m.content.isEmpty
                      ? 'Hata: $errText'
                      : '${m.content}\n\n[Hata: $errText]',
                  durationSec: sw.elapsedMilliseconds / 1000.0,
                ),
              );
              notifyListeners();
              return;
            }

            if (event.delta != null && event.delta!.isNotEmpty) {
              finalReply += event.delta!;
              _updateMessageInActiveSession(
                assistantId,
                (m) => m.copyWith(content: finalReply),
              );
              if (liveLoopActive) {
                liveAssistantReply = LocalCommandEngine.stripActionTags(
                  finalReply,
                );
              }
              notifyListeners();
            }

            if (event.fullText != null) {
              finalReply = event.fullText!;
              _updateMessageInActiveSession(
                assistantId,
                (m) => m.copyWith(content: finalReply),
              );
              if (liveLoopActive) {
                liveAssistantReply = LocalCommandEngine.stripActionTags(
                  finalReply,
                );
              }
              notifyListeners();
            }

            if (event.done) {
              final dataActs = <Map<String, dynamic>>[];
              for (final act in event.actions) {
                final type = act['type']?.toString() ?? '';
                if (_dataToolTypes.contains(type)) {
                  dataActs.add(act);
                } else {
                  phoneActs.add(act);
                }
              }
              pendingDataTools = dataActs;
              doneBanners = [for (final a in dataActs) _describeDataTool(a)];
              final elapsed = sw.elapsedMilliseconds / 1000.0;
              final toolsOff = !settings.agentTools;
              _updateMessageInActiveSession(
                assistantId,
                (m) => m.copyWith(
                  content: finalReply.isEmpty && !hadError
                      ? (dataActs.isNotEmpty
                            ? (toolsOff
                                  ? "Araçlar kapalı; Ayarlar'dan Ajan araçlarını açabilirsin."
                                  : '🔎 Bakıyorum...')
                            : (phoneActs.isNotEmpty
                                  ? m.content
                                  : '(Boş yanıt döndü)'))
                      : (finalReply.isNotEmpty ? finalReply : m.content),
                  durationSec: elapsed,
                  actionBanner: doneBanners.isEmpty
                      ? null
                      : doneBanners.join(' • '),
                ),
              );
              notifyListeners();
            }
          },
          onError: (Object err) async {
            if (_streamCompleter != completer) return;
            hadError = true;
            phoneActs.clear();
            _updateMessageInActiveSession(
              assistantId,
              (m) => m.copyWith(
                content: 'Bağlantı hatası: $err',
                durationSec: sw.elapsedMilliseconds / 1000.0,
              ),
            );
            isStreaming = false;
            await persistSessions();
            notifyListeners();
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (_streamCompleter != completer) return;
            if (isStreaming) {
              isStreaming = false;
              notifyListeners();
            }
            if (!completer.isCompleted) completer.complete();
          },
        );

    await completer.future;

    if (_streamCompleter == completer && phoneActs.isEmpty && !hadError) {
      await persistSessions();
    }
    if (_streamCompleter == completer && phoneActs.isNotEmpty) {
      final banners = [...doneBanners];
      for (final act in phoneActs) {
        if (_streamCompleter != completer) return;
        try {
          final key = LocalCommandEngine.reminderActionKey(act);
          if (key != null && !seenReminders.add(key)) continue;
          final banner = await executeAnyAction(act);
          if (banner != null && banner.isNotEmpty) banners.add(banner);
        } catch (_) {
          banners.add('[${act['type']}] hata');
        }
      }
      if (_streamCompleter == completer) {
        _updateMessageInActiveSession(
          assistantId,
          (m) => m.copyWith(
            actionBanner: banners.isEmpty ? null : banners.join(' • '),
          ),
        );
        await persistSessions();
        notifyListeners();
      }
    }

    phoneTask =
        phoneTask ||
        pendingDataTools.any(
          (a) => const {
            'phone_open_app',
            'phone_snapshot',
            'phone_resume_screen',
            'screen_read',
            'phone_action',
          }.contains(a['type']),
        );
    final maxSteps = phoneTask ? 16 : 6;
    // Agent loop: run information tools and let the model answer with results.
    if (!hadError &&
        pendingDataTools.isNotEmpty &&
        settings.agentTools &&
        depth < maxSteps &&
        _streamCompleter == completer) {
      isStreaming = true;
      notifyListeners();
      final results = <String>[];
      var phoneActionUsed = false;
      for (final act in pendingDataTools) {
        if (_streamCompleter != completer) return;
        final changesPhone = const {
          'phone_open_app',
          'phone_action',
          'end_call',
          'phone_resume_screen',
          'screen_read',
          'download_file',
        }.contains(act['type']);
        if (changesPhone && phoneActionUsed) {
          results.add(
            'Hata: Bu turda ikinci telefon eylemi uygulanmadı. İlk eylemin son ekranını inceleyip sonraki turda devam et.',
          );
          continue;
        }
        if (changesPhone) phoneActionUsed = true;
        results.add(await _runDataToolTimed(act));
      }
      if (_streamCompleter != completer) return;
      final toolMsg = JarvisMessage(
        id: LocalCommandEngine.newId(),
        role: 'user',
        content:
            'ARAÇ SONUÇLARI (kullanıcı bunu görmüyor; adım ${depth + 1}/$maxSteps). İş bittiyse bu verilerle kullanıcının son isteğine doğrudan, Türkçe ve gerekiyorsa kaynak bağlantılarıyla cevap ver; '
            'iş birden fazla adım gerektiriyorsa sıradaki aracı çağır. Sonucu doğrulanmamış bir işlemi "yaptım" diye bildirme.\n\n${results.join('\n\n---\n\n')}',
        timestamp: DateTime.now(),
      );
      final cleanedFirst = LocalCommandEngine.stripActionTags(finalReply);
      final nextHistory = <JarvisMessage>[
        ...history,
        JarvisMessage(
          id: assistantId,
          role: 'assistant',
          content: cleanedFirst.isEmpty
              ? 'Araçları çalıştırıyorum.'
              : cleanedFirst,
          timestamp: DateTime.now(),
        ),
        toolMsg,
      ];
      await _streamAiReply(
        history: nextHistory,
        speakReply: speakReply,
        depth: depth + 1,
        reminderActions: seenReminders,
        phoneTask: phoneTask,
        sessionId: originId,
      );
      return;
    }

    if (!hadError && pendingDataTools.isNotEmpty && depth >= maxSteps) {
      finalReply = 'İşlem adımı sınırına ulaştım. İstenen görevin tamamlandığını doğrulayamadım.';
      _updateMessageInActiveSession(
        assistantId,
        (m) => m.copyWith(content: finalReply),
      );
      if (liveLoopActive) liveAssistantReply = finalReply;
      await persistSessions();
      notifyListeners();
    }

    if (!hadError &&
        finalReply.trim().isNotEmpty &&
        (speakReply || settings.autoTts) &&
        !liveLoopActive &&
        _streamCompleter == completer) {
      unawaited(
        speakMessage(
          assistantId,
          LocalCommandEngine.stripActionTags(finalReply),
        ),
      );
    }
  }

  String _describeDataTool(Map<String, dynamic> act) {
    final type = act['type']?.toString() ?? '';
    final arg =
        (act['query'] ??
                act['url'] ??
                act['city'] ??
                act['topic'] ??
                act['from'] ??
                '')
            .toString();
    const icons = {
      'web_search': '🔎 Web araması',
      'fetch_url': '🌐 Sayfa okunuyor',
      'wikipedia': '📚 Vikipedi',
      'weather': '🌤️ Hava durumu',
      'currency': '💱 Döviz',
      'news': '📰 Haberler',
      'location': '📍 Konum',
      'list_apps': '📱 Uygulamalar',
      'app_usage': '📊 Kullanım',
    };
    return '${icons[type] ?? type}${arg.isEmpty ? '' : ': $arg'}';
  }

  final Map<String, ({WebPage page, DateTime at})> _pageCache = {};

  Future<WebPage> fetchPageCached(String url) async {
    final hit = _pageCache[url];
    if (hit != null && DateTime.now().difference(hit.at).inMinutes < 10) {
      return hit.page;
    }
    final page = await WebTools.fetchPage(url, client: httpClient);
    if (page.ok) {
      if (_pageCache.length > 20) _pageCache.remove(_pageCache.keys.first);
      _pageCache[url] = (page: page, at: DateTime.now());
    }
    return page;
  }

  Future<String> _buildUrlContext(String text) async {
    if (!settings.agentTools) return '';
    final urls = WebTools.extractUrls(text).take(2).toList();
    if (urls.isEmpty) return '';
    final parts = <String>[];
    for (final u in urls) {
      final norm = WebTools.normalizeUrl(u);
      if (norm == null) continue;
      if (WebTools.looksLikeDirectMedia(norm)) {
        parts.add(
          '[$norm doğrudan bir dosya/medya bağlantısı. İndirmek için download_file aracını kullanabilirsin.]',
        );
        continue;
      }
      final page = await fetchPageCached(norm);
      if (!page.ok) {
        parts.add('[$norm getirilemedi: ${page.error}]');
        continue;
      }
      final body = page.text.length > 9000
          ? '${page.text.substring(0, 9000)}…'
          : page.text;
      final media = page.media.isEmpty
          ? ''
          : '\nSayfadaki medya: ${page.media.take(5).map((m) => '${m.kind}: ${m.url}').join(' | ')}';
      parts.add(
        '### Otomatik getirilen sayfa: ${page.title}\nURL: ${page.finalUrl.isEmpty ? norm : page.finalUrl}\nAçıklama: ${page.description}$media\n\n$body',
      );
    }
    if (parts.isEmpty) return '';
    return '[Ege web erişimi — mesajdaki bağlantıların içeriği aşağıda]\n\n${parts.join('\n\n---\n\n')}';
  }

  Future<String> _runDataTool(Map<String, dynamic> act) async {
    final type = act['type']?.toString() ?? '';
    try {
      switch (type) {
        case 'web_search':
          final q = (act['query'] ?? '').toString().trim();
          if (q.isEmpty) return '[web_search] sorgu boş';
          final results = await WebTools.search(
            q,
            client: httpClient,
            limit: 6,
          );
          if (results.isEmpty) return '[web_search "$q"] sonuç bulunamadı.';
          final buf = StringBuffer('[web_search "$q"] sonuçları:\n');
          for (var i = 0; i < results.length; i++) {
            final r = results[i];
            buf.writeln('${i + 1}. ${r.title} — ${r.url}\n   ${r.snippet}');
          }
          final pages = await Future.wait(
            results.take(2).map((r) => fetchPageCached(r.url)),
          );
          for (final p in pages.where((p) => p.ok && p.text.isNotEmpty)) {
            final t = p.text.length > 3500
                ? '${p.text.substring(0, 3500)}…'
                : p.text;
            buf.writeln('\n#### ${p.title} (${p.finalUrl})\n$t');
          }
          return buf.toString();
        case 'fetch_url':
          final url = WebTools.normalizeUrl((act['url'] ?? '').toString());
          if (url == null) return '[fetch_url] geçersiz URL';
          final page = await fetchPageCached(url);
          if (!page.ok) return '[fetch_url $url] hata: ${page.error}';
          final t = page.text.length > 10000
              ? '${page.text.substring(0, 10000)}…'
              : page.text;
          return '[fetch_url ${page.finalUrl}]\nBaşlık: ${page.title}\nAçıklama: ${page.description}\nMedya: ${page.media.take(6).map((m) => m.url).join(', ')}\n\n$t';
        case 'wikipedia':
          final q = (act['query'] ?? '').toString();
          final s = await WebTools.wikipediaSummary(q, client: httpClient);
          return s == null
              ? '[wikipedia "$q"] bulunamadı'
              : '[wikipedia] ${s.title}: ${s.extract} (${s.url})';
        case 'weather':
          final city = (act['city'] ?? '').toString().trim();
          WeatherReport? w;
          if (city.isNotEmpty) {
            w = await WebTools.weather(city: city, client: httpClient);
          } else {
            final loc = await DeviceBridge.getCurrentLocation();
            w = loc == null
                ? await WebTools.weather(city: 'İstanbul', client: httpClient)
                : await WebTools.weather(
                    lat: loc.lat,
                    lon: loc.lon,
                    client: httpClient,
                  );
          }
          return w == null
              ? '[weather] alınamadı'
              : '[weather] ${w.toTurkishSummary()}';
        case 'currency':
          final amtRaw = act['amount'];
          final amount =
              (amtRaw is num ? amtRaw : num.tryParse('$amtRaw'))?.toDouble() ??
              1.0;
          final from = (act['from'] ?? 'USD').toString().toUpperCase();
          final to = (act['to'] ?? 'TRY').toString().toUpperCase();
          final q = await WebTools.convertCurrency(
            amount: amount,
            from: from,
            to: to,
            client: httpClient,
          );
          return q == null
              ? '[currency] alınamadı'
              : '[currency] $amount $from = ${q.converted.toStringAsFixed(4)} $to (kur ${q.rate}, tarih ${q.date?.toIso8601String().split('T').first ?? '-'})';
        case 'news':
          final topic = (act['topic'] ?? act['query'] ?? '').toString().trim();
          final items = await WebTools.news(
            topic: topic.isEmpty ? null : topic,
            client: httpClient,
            limit: 10,
          );
          if (items.isEmpty) return '[news] haber bulunamadı';
          return '[news${topic.isEmpty ? '' : ' "$topic"'}]\n${items.map((n) => '- ${n.title} (${n.source}) ${n.link}').join('\n')}';
        case 'location':
          final loc = await DeviceBridge.getCurrentLocation();
          return loc == null
              ? '[location] konum alınamadı (izin/GPS kapalı)'
              : '[location] lat ${loc.lat}, lon ${loc.lon}, doğruluk ${loc.accuracy.round()} m';
        case 'list_apps':
          if (installedApps.isEmpty) await refreshInstalledApps();
          return '[list_apps] ${installedApps.length} uygulama: ${installedApps.map((a) => a.name).join(', ')}';
        case 'app_usage':
          if (!await DeviceBridge.hasUsageAccess()) {
            return '[app_usage] Kullanım erişimi izni yok; kullanıcıya Ayarlar > Kullanım erişimi iznini vermesini söyle.';
          }
          final usage = await DeviceBridge.getAppUsageStats(days: 1);
          return '[app_usage bugün] ${usage.take(15).map((u) => '${u.name}: ${(u.foregroundMs / 60000).round()} dk').join(', ')}';
      }
      if (JarvisAgent.agentToolTypes.contains(type)) {
        return await runAgentTool(act);
      }
      return '[$type] desteklenmiyor';
    } catch (e) {
      return '[$type] hata: $e';
    }
  }

  /// Ajan araçları kendi günlüklerini tutar; diğer veri araçlarını burada ölç.
  Future<String> _runDataToolTimed(Map<String, dynamic> act) async {
    final type = act['type']?.toString() ?? '';
    if (JarvisAgent.agentToolTypes.contains(type)) return _runDataTool(act);
    final sw = Stopwatch()..start();
    final out = await _runDataTool(act);
    logTool(
      type,
      (act['query'] ?? act['url'] ?? act['city'] ?? act['topic'] ?? '')
          .toString(),
      sw.elapsedMilliseconds,
      !out.contains('] hata'),
    );
    return out;
  }

  // -------------------- DOWNLOADS --------------------

  List<DownloadItem> downloads = [];
  Timer? _downloadPoller;

  Future<void> refreshDownloads() async {
    downloads = await DeviceBridge.queryDownloads();
    notifyListeners();
  }

  void setDownloadPolling(bool active) {
    if (active) {
      _downloadPoller ??= Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => unawaited(refreshDownloads()),
      );
      unawaited(refreshDownloads());
    } else {
      _downloadPoller?.cancel();
      _downloadPoller = null;
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Future<String> downloadFile(
    String url, {
    String? fileName,
    String? expectedKind,
  }) async {
    final norm = WebTools.normalizeUrl(url);
    if (norm == null) return 'Geçersiz bağlantı: $url';
    final probe = await WebTools.probeUrl(norm, client: httpClient);
    final name = (fileName != null && fileName.trim().isNotEmpty)
        ? fileName.trim()
        : (probe.ok && probe.fileName.isNotEmpty
              ? probe.fileName
              : WebTools.guessFileName(norm));
    final mime = probe.ok && probe.contentType.isNotEmpty
        ? probe.contentType.split(';').first.trim()
        : null;
    if (expectedKind == 'image' &&
        (!probe.ok || !(mime ?? '').startsWith('image/'))) {
      return 'Hata: Bağlantı gerçek bir resim olarak doğrulanamadı; HTML sayfası resim diye indirilmedi. page_media ile gerçek resmi bul veya uygulamanın Resmi indir menüsünü kullan.';
    }
    final id = await DeviceBridge.enqueueManagedDownload(
      url: probe.ok && probe.finalUrl.isNotEmpty ? probe.finalUrl : norm,
      fileName: name,
      mimeType: mime,
    );
    if (id == null) {
      return '⬇️ İndirme başlatılamadı ($name). Android indirme yöneticisi kullanılamıyor olabilir.';
    }
    unawaited(refreshDownloads());
    final size = (probe.length ?? 0) > 0
        ? ' • ${formatBytes(probe.length!)}'
        : '';
    final pageNote = (mime ?? '').contains('html')
        ? '\n\nℹ️ Bu bağlantı bir web sayfası; sayfanın HTML kopyası indiriliyor. Sayfadaki videoyu istiyorsanız "video indir <bağlantı>" deyin.'
        : '';
    return '⬇️ **$name** indiriliyor$size → `İndirilenler/Ege`. İlerlemeyi Araçlar › İndir sekmesinden izleyebilirsiniz.$pageNote';
  }

  int _videoScore(MediaCandidate m) {
    final u = m.url.toLowerCase();
    var s = 0;
    if (u.contains('.mp4')) s += 50;
    if (u.contains('.webm')) s += 30;
    if (u.contains('.m3u8') || u.contains('.mpd')) s -= 60;
    if (m.source == 'og' || m.source == 'direct') s += 20;
    if (m.source == 'video-tag' || m.source == 'source-tag') s += 15;
    if (u.contains('1080')) s += 8;
    if (u.contains('720')) s += 5;
    return s;
  }

  @override
  Future<String> downloadVideo(String url) async {
    final norm = WebTools.normalizeUrl(url);
    if (norm == null) return 'Geçersiz bağlantı: $url';
    if (WebTools.looksLikeDirectMedia(norm)) return downloadFile(norm);
    final media = await WebTools.findMedia(norm, client: httpClient);
    final videos =
        media.where((m) => m.kind == 'video' && _videoScore(m) > -20).toList()
          ..sort((a, b) => _videoScore(b).compareTo(_videoScore(a)));
    if (videos.isNotEmpty) {
      final msg = await downloadFile(videos.first.url);
      return '🎬 Sayfada video bulundu.\n\n$msg';
    }
    return downloadWithYtDlp(
      norm,
      reasonPrefix: '🎬 Bu sayfa doğrudan video bağlantısı sunmuyor (YouTube, Instagram, TikTok, X vb. akış kullanır).',
    );
  }

  Future<String> downloadWithYtDlp(
    String url, {
    String reasonPrefix = '',
  }) async {
    final res = await DeviceBridge.runTermuxCommand(
      executable: '/data/data/com.termux/files/usr/bin/yt-dlp',
      args: [
        '-f',
        'bv*[ext=mp4][height<=1080]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b',
        '--merge-output-format',
        'mp4',
        '--no-mtime',
        '--restrict-filenames',
        '-o',
        '/storage/emulated/0/Download/Ege/%(title).80s.%(ext)s',
        url,
      ],
      workDir: '/data/data/com.termux/files/home',
      background: true,
    );
    final prefix = reasonPrefix.isEmpty ? '' : '$reasonPrefix\n\n';
    switch (res) {
      case 'OK':
        return '$prefix✅ Termux üzerinde **yt-dlp** ile indirme başlatıldı → `İndirilenler/Ege`. (Yalnızca indirme hakkınız olan içerikleri indirin.)';
      case 'PERMISSION_NEEDED':
        return '$prefix🔐 Termux komut izni istendi. İzni verip tekrar deneyin. Ayrıca Termux\'ta `~/.termux/termux.properties` dosyasına `allow-external-apps=true` ekleyin.';
      case 'TERMUX_NOT_INSTALLED':
        return '$prefix'
            'Bu tür siteler için telefonda **Termux + yt-dlp** kurulursa Ege otomatik indirebilir:\n'
            '1. F-Droid\'den Termux\'u kurun\n'
            '2. Termux\'ta: `pkg install python ffmpeg && pip install yt-dlp && termux-setup-storage`\n'
            '3. `echo "allow-external-apps=true" >> ~/.termux/termux.properties`\n\n'
            'Alternatif: Araçlar › İndir sekmesindeki **Paylaş** düğmesiyle bağlantıyı bir indirici uygulamaya gönderebilirsiniz.';
      default:
        return '${prefix}Termux komutu çalıştırılamadı: $res';
    }
  }

  Future<bool> openDownload(int id) => DeviceBridge.openDownload(id);

  Future<void> removeDownload(int id) async {
    await DeviceBridge.removeDownload(id);
    await refreshDownloads();
  }

  Future<String?> saveTextToDownloads(
    String fileName,
    String content, {
    String mimeType = 'text/markdown',
  }) {
    return DeviceBridge.saveBytesToDownloads(
      bytes: Uint8List.fromList(utf8.encode(content)),
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  // -------------------- DEEP RESEARCH --------------------

  bool researchRunning = false;
  ResearchProgress? researchProgress;
  String researchQuestion = '';
  bool _researchCancelled = false;

  void cancelResearch() {
    _researchCancelled = true;
    notifyListeners();
  }

  @override
  Future<String> startDeepResearch(String question) async {
    if (researchRunning) {
      return '🔬 Zaten "$researchQuestion" araştırması sürüyor. Bitince yenisini başlatabilirsiniz.';
    }
    unawaited(runDeepResearch(question, postToChat: true));
    return '🔬 **"$question"** için derin araştırma başlatıldı: sorgular planlanıyor, web kaynakları taranıp okunuyor. Rapor hazır olunca buraya ve Stüdyo\'ya eklenecek.';
  }

  Future<ResearchReport?> runDeepResearch(
    String question, {
    bool postToChat = false,
  }) async {
    if (researchRunning) return null;
    final researchSid = activeSessionId;
    researchRunning = true;
    researchQuestion = question;
    researchProgress = null;
    _researchCancelled = false;
    notifyListeners();

    final report = await DeepResearchService.run(
      question: question,
      llm: (prompt) async {
        final r = await _runOneShotAi(prompt);
        if (!r.ok) throw Exception(r.text);
        return r.text;
      },
      client: httpClient,
      onProgress: (p) {
        researchProgress = p;
        notifyListeners();
      },
      isCancelled: () => _researchCancelled,
    );

    researchRunning = false;
    if (report.ok) {
      final artifact = StudyArtifact(
        id: LocalCommandEngine.newId(),
        kind: 'research',
        title: 'Araştırma: $question',
        content: report.markdown,
        createdAt: DateTime.now(),
      );
      studies.insert(0, artifact);
      await _storage.saveStudies(studies);
    }
    if (postToChat) {
      final msg = JarvisMessage(
        id: LocalCommandEngine.newId(),
        role: 'assistant',
        content: report.ok
            ? report.markdown
            : '🔬 Araştırma tamamlanamadı: ${report.error}',
        timestamp: DateTime.now(),
        modelUsed: 'Derin Araştırma',
        durationSec: report.elapsed.inMilliseconds / 1000.0,
        actionBanner: report.ok
            ? '🔬 ${report.sources.length} kaynak tarandı'
            : null,
      );
      await _appendToSession(researchSid, msg);
    }
    notifyListeners();
    return report;
  }

  Future<void> _generateImageInChat(String prompt) async {
    final assistantId = LocalCommandEngine.newId();
    final placeholder = JarvisMessage(
      id: assistantId,
      role: 'assistant',
      content: '🎨 Görsel üretiliyor (${settings.model})...',
      timestamp: DateTime.now(),
      modelUsed: settings.model,
    );
    _replaceSession(
      activeSession.copyWith(
        updatedAt: DateTime.now(),
        messages: [...activeSession.messages, placeholder],
      ),
    );
    isStreaming = true;
    notifyListeners();

    final sw = Stopwatch()..start();
    final res = await AiClient.generateImage(
      settings: settings,
      prompt: prompt,
      client: httpClient,
    );
    sw.stop();

    if (!res.ok || res.bytes == null) {
      _updateMessageInActiveSession(
        assistantId,
        (m) => m.copyWith(
          content: 'Görsel üretilemedi: ${res.error ?? 'Bilinmeyen hata'}',
          durationSec: sw.elapsedMilliseconds / 1000.0,
        ),
      );
      isStreaming = false;
      await persistSessions();
      notifyListeners();
      return;
    }

    final ext = res.mimeType.contains('jpeg') ? 'jpg' : 'png';
    final fileName = 'jarvis_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final savedPath = await DeviceBridge.saveGeneratedImage(
      res.bytes!,
      fileName,
    );
    final att = ChatAttachment(
      id: LocalCommandEngine.newId(),
      name: fileName,
      mimeType: res.mimeType,
      kind: 'image',
      localPath: savedPath,
      base64Data: savedPath == null ? base64Encode(res.bytes!) : null,
    );
    final caption = (res.caption != null && res.caption!.isNotEmpty)
        ? res.caption!
        : '🎨 **${settings.model}** ile görsel oluşturuldu.';
    _updateMessageInActiveSession(
      assistantId,
      (m) => m.copyWith(
        content: caption,
        attachments: [att],
        durationSec: sw.elapsedMilliseconds / 1000.0,
        actionBanner: '🖼️ Görsel oluşturuldu',
      ),
    );
    isStreaming = false;
    await persistSessions();
    notifyListeners();
  }

  void _updateMessageInActiveSession(
    String messageId,
    JarvisMessage Function(JarvisMessage) transform,
  ) {
    final s = sessions
        .where((s) => s.messages.any((m) => m.id == messageId))
        .firstOrNull;
    if (s == null) return;
    final list = List<JarvisMessage>.from(s.messages);
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    list[idx] = transform(list[idx]);
    _replaceSession(s.copyWith(messages: list, updatedAt: DateTime.now()));
  }

  Future<void> stopStreaming() async {
    final oldSubscription = _activeStreamSub;
    _activeStreamSub = null;
    isStreaming = false;
    final c = _streamCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _streamCompleter = null;
    unawaited(oldSubscription?.cancel().catchError((Object _) {}));
    await persistSessions();
    notifyListeners();
  }

  // -------------------- TTS & DICTATION --------------------

  Future<void> speakMessage(String messageId, String content) async {
    if (speakingMessageId == messageId && _voice.isSpeaking) {
      await stopSpeaking();
      return;
    }
    speakingMessageId = messageId;
    notifyListeners();
    try {
      await _voice.speak(
        content,
        rate: settings.ttsRate,
        pitch: settings.ttsPitch,
        settings: settings,
        httpClient: httpClient,
      );
      if (_voice.lastError != null &&
          !_voice.usedDeviceFallback &&
          speakingMessageId == messageId) {
        liveStatusHint = 'Seslendirme başarısız: ${_voice.lastError}';
        debugPrint('[Ege] speakMessage hata: ${_voice.lastError}');
      }
    } finally {
      if (speakingMessageId == messageId) {
        speakingMessageId = null;
      }
      notifyListeners();
    }
  }

  Future<void> stopSpeaking() async {
    speakingMessageId = null;
    await _voice.stopSpeaking();
    notifyListeners();
  }

  Future<String?> toggleDictation({
    required void Function(String text) onTranscript,
  }) async {
    if (_dictationStarting) return null;
    if (isDictating) {
      if (_phoneDictationActive) {
        await DeviceBridge.stopPhoneSpeech();
        return null;
      }
      if (_wavDictationActive) {
        _wavDictationActive = false;
        _cancelDictationWatchdog();
        DeviceBridge.setMicCallbacks();
        final wavBytes = await DeviceBridge.stopMicCapture();
        unawaited(_restoreMusicAfterMic());
        isDictating = false;
        orbAmplitude = 0.0;
        notifyListeners();
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 500),
            resumeWakeWord,
          ),
        );
        if (wavBytes == null || wavBytes.length <= 44) {
          return await DeviceBridge.noSpeechReason();
        }
        if (wavBytes.length > 44) {
          final res = await transcribeSpeech(wavBytes);
          if (res.ok && res.text.trim().isNotEmpty) {
            dictationPreview = res.text.trim();
            onTranscript(dictationPreview);
            notifyListeners();
            return null;
          }
          if (!res.ok) {
            return res.error ?? 'Ses metne dönüştürülemedi.';
          }
        }
        return null;
      }

      _cancelDictationWatchdog();
      unawaited(_restoreMusicAfterMic());
      isDictating = false;
      notifyListeners();
      unawaited(resumeWakeWord());
      return null;
    }

    _dictationStarting = true;
    try {
      return await _startDictation(onTranscript);
    } finally {
      _dictationStarting = false;
    }
  }

  Future<String?> _startDictation(
    void Function(String text) onTranscript,
  ) async {
    dictationPreview = '';
    isDictating = true;
    notifyListeners();
    var startGen = ++_dictationGeneration;
    await DeviceBridge.wakeWordPause();
    wakeWordActive = false;

    await SpeakerIdentity.instance.load();
    if (!SpeakerIdentity.instance.enabled && !_phoneSttDown) {
      final token = ++_dictationGeneration;
      _phoneDictationActive = true;
      final sw = Stopwatch()..start();
      final result = await DeviceBridge.recognizePhoneSpeech();
      if (token != _dictationGeneration) return null;
      _phoneDictationActive = false;
      if (_phoneSttFailed(result.status)) {
        // Cihaz içi model yok: aynı dikteyi kayıt + bulut çözümlemeyle sürdür.
        _phoneSttDown = true;
        startGen = token;
      } else {
        isDictating = false;
        if (result.status == 'OK') {
          lastSttInfo =
              'Telefon STT • ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} sn';
          dictationPreview = result.text.trim();
          onTranscript(dictationPreview);
        }
        notifyListeners();
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 500),
            resumeWakeWord,
          ),
        );
        return result.status == 'PERMISSION_NEEDED'
            ? _micPermissionText
            : result.status == 'NO_SPEECH'
            ? 'Konuşma duyulmadı. Tekrar deneyin.'
            : result.status == 'OK' || result.status == 'CANCELLED'
            ? null
            : 'Android yerel STT hazır değil. Türkçe dil desteğini kontrol et.';
      }
    }

    if (usesWavCaptureStt) {
      warmUpWhisper();
      DeviceBridge.setMicCallbacks(
        onLevel: (level) {
          orbAmplitude = level.clamp(0.05, 1.0);
          notifyListeners();
        },
        onSilence: () {
          if (isDictating && _wavDictationActive) {
            unawaited(toggleDictation(onTranscript: onTranscript));
          }
        },
      );
      // Dikte: düşünme payı için 1,3 sn sessizlikte biter.
      await _pauseMusicForMic();
      final micStatus = await DeviceBridge.startMicCapture(
        endSilenceMs: 1300,
        noSpeechMs: 8000,
      );
      if (micStatus == 'OK') {
        if (!isDictating || startGen != _dictationGeneration) {
          // Kullanıcı bu arada iptal etti: açılan mikrofonu kapat.
          DeviceBridge.setMicCallbacks();
          await DeviceBridge.cancelMicCapture();
          unawaited(_restoreMusicAfterMic());
          unawaited(resumeWakeWord());
          return null;
        }
        _wavDictationActive = true;
        _cancelDictationWatchdog();
        _dictationWatchdog = Timer(const Duration(seconds: 30), () {
          // onMicSilence hiç gelmezse kaydı kendimiz bitir.
          if (isDictating && _wavDictationActive) {
            unawaited(toggleDictation(onTranscript: onTranscript));
          }
        });
        return null;
      }
      DeviceBridge.setMicCallbacks();
      unawaited(_restoreMusicAfterMic());
      if (micStatus == 'PERMISSION_NEEDED') {
        isDictating = false;
        notifyListeners();
        unawaited(resumeWakeWord());
        return _micPermissionText;
      }
    }
    isDictating = false;
    notifyListeners();
    unawaited(resumeWakeWord());
    return 'Mikrofon başlatılamadı. Başka bir uygulama mikrofonu kullanıyor olabilir.';
  }

  // -------------------- Ege LIVE (HANDS-FREE & REALTIME WS) --------------------

  String _liveTypedRequest = '';
  RealtimeLiveSession? _liveSocket;

  Future<void> _startStreamingVoice(int generation, String key) async {
    _liveTypedRequest = '';
    final ready = Completer<bool>();
    var lost = false;
    Future<String?>? contextualAction;
    Future<String>? executedCommand;
    var heard = '';
    var reply = '';
    void disconnected() {
      if (lost) return;
      lost = true;
      if (!ready.isCompleted) ready.complete(false);
      if (_ownsLiveTurn(generation) && _liveSocket != null) {
        unawaited(_resumeLocalVoice(generation));
      }
    }
    try {
      liveStatusHint = 'Gemini Live bağlantısı kuruluyor…';
      livePhase = LiveVoicePhase.thinking;
      notifyListeners();
      final session = await RealtimeLiveSession.connectGeminiLive(
        settings: settings.copyWith(provider: ApiProvider.geminiDirect, apiKey: key),
        onReady: () { if (!ready.isCompleted) ready.complete(true); },
        onError: (_) => disconnected(),
        onClosed: disconnected,
        onInterrupted: () {
          if (!_ownsLiveTurn(generation)) return;
          unawaited(DeviceBridge.interruptLiveAudioStream());
          livePhase = LiveVoicePhase.listening;
          liveStatusHint = 'Seni dinliyorum…';
          notifyListeners();
        },
        onAudioPcmDelta: (pcm) {
          if (!_ownsLiveTurn(generation)) return;
          unawaited(DeviceBridge.feedLiveAudioPcm(pcm));
          if (livePhase == LiveVoicePhase.speaking) return;
          livePhase = LiveVoicePhase.speaking;
          liveStatusHint = 'Konuşarak araya girebilirsin.';
          notifyListeners();
        },
        onUserTranscript: (text, {bool append = false}) {
          if (!_ownsLiveTurn(generation)) return;
          _liveTypedRequest = '';
          heard = append ? heard + text : text;
          liveTranscript = heard;
          notifyListeners();
        },
        onAssistantTranscript: (text, {bool append = false}) {
          if (!_ownsLiveTurn(generation)) return;
          reply = append ? reply + text : text;
          liveAssistantReply = reply;
          notifyListeners();
        },
        onTurnComplete: () {
          if (!_ownsLiveTurn(generation)) return;
          if (LocalCommandEngine.isAssistantExit(heard)) {
            unawaited(closeAssistant());
            return;
          }
          if (contextualAction == null && _isContextual(heard)) {
            final request = heard;
            final chat = activeSessionId;
            unawaited(_currentAppRequest(request).then((outcome) {
              if (outcome == null || !_ownsLiveTurn(generation) || activeSessionId != chat) return;
              liveAssistantReply = outcome;
              notifyListeners();
            }));
          }
          contextualAction = null;
          executedCommand = null;
          final session = activeSession;
          final messages = [
            ...session.messages,
            for (final item in [('user', heard), ('assistant', reply)])
              if (item.$2.trim().isNotEmpty)
                JarvisMessage(id: LocalCommandEngine.newId(), role: item.$1, content: item.$2.trim(), timestamp: DateTime.now()),
          ];
          if (messages.length != session.messages.length) {
            _replaceSession(session.copyWith(messages: messages, updatedAt: DateTime.now()));
            unawaited(persistSessions());
          }
          heard = '';
          _liveTypedRequest = '';
          reply = '';
          livePhase = LiveVoicePhase.listening;
          liveStatusHint = 'Seni dinliyorum…';
          notifyListeners();
        },
      );
      if (!_ownsLiveTurn(generation)) { await session.close(); return; }
      _liveSocket = session;
      final liveChat = activeSessionId;
      Future<String> executeRequest(String request) async {
        if (!_ownsLiveTurn(generation) || activeSessionId != liveChat) return 'Oturum sona erdi.';
        if (_isContextual(request)) {
          return await (contextualAction ??= _currentAppRequest(request)) ?? 'Ekran okunamadı.';
        }
        final local = await runLocalCommand(request);
        if (local != null && local.handled) return local.reply;
        if (!_ownsLiveTurn(generation) || !settings.agentTools) {
          return 'Bu işlem için telefon araçları kullanılamıyor.';
        }
        return runAgentHeadless(request, allowActions: true, maxRounds: 8,
          isActive: () => _ownsLiveTurn(generation) && activeSessionId == liveChat,
          allowOnly: const {'list_apps', 'phone_open_app', 'phone_snapshot', 'phone_action', 'phone_resume_screen', 'screen_read', 'web_search', 'fetch_url', 'create_project', 'create_text_file', 'create_spreadsheet', 'create_document'},
        );
      }
      session.onToolCommand = (cmd) async {
        if (!_ownsLiveTurn(generation) || activeSessionId != liveChat) return 'Oturum sona erdi.';
        final request = (_liveTypedRequest.isNotEmpty ? _liveTypedRequest : heard).trim();
        if (!RealtimeLiveSession.commandMatchesTranscript(cmd, request)) {
          return 'Komut kullanıcının söylediği cümleyle eşleşmedi.';
        }
        return await (executedCommand ??= executeRequest(request));
      };
      final connected = await ready.future.timeout(const Duration(seconds: 8), onTimeout: () => false);
      if (!_ownsLiveTurn(generation)) return;
      if (!connected || !await DeviceBridge.openLiveAudioStream()) {
        await _resumeLocalVoice(generation);
        return;
      }
      if (!_ownsLiveTurn(generation)) return;
      DeviceBridge.setLiveAudioCallbacks(onLivePcmChunk: session.sendAudioPcm);
      final mic = await DeviceBridge.startLivePcmMic(bargeIn: true);
      if (!_ownsLiveTurn(generation)) return;
      if (mic != 'OK') { await _resumeLocalVoice(generation); return; }
      lastSttInfo = 'Gemini Live';
      livePhase = LiveVoicePhase.listening;
      liveStatusHint = 'Seni dinliyorum…';
      notifyListeners();
    } catch (_) {
      if (_ownsLiveTurn(generation)) await _resumeLocalVoice(generation);
    }
  }

  Future<void> _resumeLocalVoice(int generation) async {
    if (!_ownsLiveTurn(generation)) return;
    final next = ++_liveTurnGeneration;
    final socket = _liveSocket;
    _liveSocket = null;
    DeviceBridge.setLiveAudioCallbacks();
    await DeviceBridge.stopLivePcmMic();
    await DeviceBridge.closeLiveAudioStream();
    await socket?.close();
    if (_ownsLiveTurn(next)) await _runLiveTurn();
  }

  Future<void> startLiveSession() async {
    if (liveLoopActive) return;
    liveLoopActive = true;
    final generation = ++_liveTurnGeneration;
    if (isDictating) {
      _dictationGeneration++;
      _phoneDictationActive = false;
      _wavDictationActive = false;
      isDictating = false;
      _cancelDictationWatchdog();
      await DeviceBridge.cancelPhoneSpeech();
      await DeviceBridge.cancelMicCapture();
      await _restoreMusicAfterMic();
    }
    await stopSpeaking();
    if (!_ownsLiveTurn(generation)) return;
    // realme ekran kapanınca / arka planda uygulamayı donduruyor: Canlı Ses
    // sürerken ön plan servisi (bildirimde "Durdur") açık kalır.
    unawaited(
      keepAlive('live', true, text: 'Konuşabilirsin • bitirmek için "dur" de'),
    );
    // Mikrofon tek: uyandırma dinlemesini Canlı Ses bitene kadar durdur.
    await DeviceBridge.wakeWordPause();
    wakeWordActive = false;
    if (!_ownsLiveTurn(generation)) return;
    liveAssistantReply = '';
    liveTranscript = '';
    orbAmplitude = 0.0;

    await SpeakerIdentity.instance.load();
    if (!_ownsLiveTurn(generation)) return;
    final key = AiClient.geminiKeyFor(settings);
    if (key.isNotEmpty && !SpeakerIdentity.instance.enabled) {
      await _startStreamingVoice(generation, key);
      return;
    }
    await _runLiveTurn();
  }

  Future<void> stopLiveSession() async {
    liveLoopActive = false;
    final hadLiveCapture = _liveCapture != null;
    _invalidateLiveTurn();
    unawaited(keepAlive('live', false));
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 800), resumeWakeWord),
    );
    livePhase = LiveVoicePhase.idle;
    liveStatusHint = 'Dokun ve konuşmaya başla';
    orbAmplitude = 0.0;

    DeviceBridge.setLiveAudioCallbacks();
    DeviceBridge.setMicCallbacks();
    if (_wavDictationActive || hadLiveCapture) {
      _wavDictationActive = false;
      unawaited(DeviceBridge.cancelMicCapture());
    }

    unawaited(DeviceBridge.stopLivePcmMic());
    unawaited(DeviceBridge.closeLiveAudioStream());

    _pendingLiveAnnouncements.clear();
    await _voice.stopSpeaking();
    if (isStreaming) {
      await stopStreaming();
    }
    unawaited(_restoreMusicAfterMic());
    notifyListeners();
  }

  Future<void> interruptAndListenLive() async {
    if (!liveLoopActive) {
      await startLiveSession();
      return;
    }

    if (_liveSocket != null) {
      await DeviceBridge.interruptLiveAudioStream();
      livePhase = LiveVoicePhase.listening;
      liveStatusHint = 'Seni dinliyorum…';
      notifyListeners();
      return;
    }
    _invalidateLiveTurn();
    final generation = _liveTurnGeneration;
    DeviceBridge.setMicCallbacks();
    await DeviceBridge.cancelMicCapture();
    await _voice.stopSpeaking();
    if (isStreaming) {
      await stopStreaming();
    }
    if (_ownsLiveTurn(generation)) await _runLiveTurn();
  }

  Future<void> sendRealtimeTextPrompt(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    if (LocalCommandEngine.isAssistantExit(trimmed)) {
      await closeAssistant();
      return;
    }
    final socket = _liveSocket;
    if (socket != null && pendingAttachments.isEmpty) {
      _liveTypedRequest = trimmed;
      socket.sendTextPrompt(trimmed);
      return;
    }
    if (socket != null) {
      await stopLiveSession();
    }
    if (!liveLoopActive) {
      liveLoopActive = true;
    }
    _invalidateLiveTurn();
    final generation = _liveTurnGeneration;
    DeviceBridge.setMicCallbacks();
    await DeviceBridge.cancelMicCapture();
    await _voice.stopSpeaking();
    if (isStreaming) await stopStreaming();
    if (!_ownsLiveTurn(generation)) return;
    await DeviceBridge.wakeWordPause();
    wakeWordActive = false;
    if (!_ownsLiveTurn(generation)) return;
    unawaited(
      keepAlive('live', true, text: 'Konuşabilirsin • bitirmek için "dur" de'),
    );
    liveTranscript = trimmed;
    notifyListeners();
    await _processLivePrompt(trimmed);
  }

  Future<({bool available, bool permissionDenied, String text})>
  _captureAndTranscribeTurnWav(int generation) async {
    final duplex = _duplexCapture;
    if (duplex != null) return _finishDuplexTurn(generation, duplex);
    await SpeakerIdentity.instance.load();
    if (!SpeakerIdentity.instance.enabled && !_phoneSttDown) {
      _phoneLiveActive = true;
      liveStatusHint = 'Seni dinliyorum...';
      notifyListeners();
      final sw = Stopwatch()..start();
      final result = await DeviceBridge.recognizePhoneSpeech();
      if (!_ownsLiveTurn(generation)) {
        return (available: true, permissionDenied: false, text: '');
      }
      _phoneLiveActive = false;
      if (result.status == 'PERMISSION_NEEDED') {
        return (available: false, permissionDenied: true, text: '');
      }
      if (result.status == 'OK') {
        lastSttInfo =
            'Telefon STT • ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} sn';
        liveTranscript = result.text.trim();
        notifyListeners();
        return (available: true, permissionDenied: false, text: liveTranscript);
      }
      if (result.status == 'CANCELLED' || result.status == 'NO_SPEECH') {
        liveStatusHint = result.status == 'NO_SPEECH' ? 'Konuşma duyulmadı.' : 'Dinleme iptal edildi.';
        return (available: true, permissionDenied: false, text: '');
      }
      // Cihaz içi model yok: aynı turu kayıt + bulut çözümlemeyle sürdür.
      _phoneSttDown = true;
      debugPrint(
        '[Ege] telefon STT kullanılamıyor (${result.status}); kayıt moduna geçildi',
      );
    }
    warmUpWhisper();
    final wavCompleter = Completer<Uint8List?>();
    _liveCapture = wavCompleter;
    var stopping = false;
    Future<void> finishCapture() async {
      if (!_ownsLiveTurn(generation) || stopping || wavCompleter.isCompleted) {
        return;
      }
      stopping = true;
      final bytes = await DeviceBridge.stopMicCapture();
      if (!wavCompleter.isCompleted) wavCompleter.complete(bytes);
    }

    DeviceBridge.setMicCallbacks(
      onLevel: (lvl) {
        if (!_ownsLiveTurn(generation)) return;
        orbAmplitude = lvl.clamp(0.05, 1.0);
        notifyListeners();
      },
      onSilence: () => unawaited(finishCapture()),
    );

    // Canlı oturum boyunca müzik duraklı kalır; stopLiveSession geri açar.
    await _pauseMusicForMic();
    if (!_ownsLiveTurn(generation)) {
      _liveCapture = null;
      DeviceBridge.setMicCallbacks();
      return (available: true, permissionDenied: false, text: '');
    }
    // Local live capture avoids recognizer tones and ends after a short natural pause.
    final micStatus = await DeviceBridge.startMicCapture(
      endSilenceMs: 560,
      noSpeechMs: 8000,
    );
    if (!_ownsLiveTurn(generation)) {
      return (available: true, permissionDenied: false, text: '');
    }
    if (micStatus == 'PERMISSION_NEEDED') {
      _liveCapture = null;
      DeviceBridge.setMicCallbacks();
      return (available: false, permissionDenied: true, text: '');
    }
    if (micStatus != 'OK') {
      _liveCapture = null;
      DeviceBridge.setMicCallbacks();
      return (available: false, permissionDenied: false, text: '');
    }

    liveStatusHint = 'Seni dinliyorum...';
    notifyListeners();

    final deadline = Timer(
      const Duration(seconds: 24),
      () => unawaited(finishCapture()),
    );
    final Uint8List? wavBytes;
    try {
      wavBytes = await wavCompleter.future;
      _liveLog('kayıt bitti bytes=${wavBytes?.length ?? 0}');
    } finally {
      deadline.cancel();
    }
    if (!_ownsLiveTurn(generation)) {
      return (available: true, permissionDenied: false, text: '');
    }
    _liveCapture = null;
    DeviceBridge.setMicCallbacks();
    orbAmplitude = 0.0;

    if (!liveLoopActive || wavBytes == null || wavBytes.length <= 44) {
      if (liveLoopActive) {
        final why = await DeviceBridge.noSpeechReason();
        if (!_ownsLiveTurn(generation)) {
          return (available: true, permissionDenied: false, text: '');
        }
        if (why != null) {
          liveStatusHint = why;
          notifyListeners();
        }
      }
      return (available: true, permissionDenied: false, text: '');
    }

    livePhase = LiveVoicePhase.thinking;
    liveStatusHint = 'Sesini çözümlüyorum...';
    notifyListeners();

    final sttSw = Stopwatch()..start();
    final sttRes = await transcribeSpeech(wavBytes);
    _liveLog(
      'tanıma ok=${sttRes.ok} motor=${sttRes.provider} '
      'karakter=${sttRes.text.length} ms=${sttSw.elapsedMilliseconds}'
      '${sttRes.ok ? '' : ' hata=${sttRes.error}'}',
    );
    if (!_ownsLiveTurn(generation)) {
      return (available: true, permissionDenied: false, text: '');
    }
    if (!sttRes.ok) {
      liveStatusHint = sttRes.error ?? 'Ses çözümlenemedi';
      notifyListeners();
      return (available: true, permissionDenied: false, text: '');
    }
    liveTranscript = sttRes.text.trim();
    notifyListeners();
    return (available: true, permissionDenied: false, text: sttRes.text.trim());
  }

  /// Tur modunu sonlandırır: ön plan servisini bırakır, uyandırmayı geri
  /// açar ve kullanıcıya nedeni gösterir.
  Future<void> _endLiveTurns(String hint) async {
    debugPrint('[Ege] canlı tur bitti: $hint');
    await stopLiveSession();
    liveStatusHint = hint;
    notifyListeners();
  }

  Future<void> _runLiveTurn() async {
    if (!liveLoopActive) return;
    final generation = _liveTurnGeneration;
    _liveLog(
      'tur başladı telefonSTT=${!_phoneSttDown} '
      'sesFiltresi=${SpeakerIdentity.instance.enabled}',
    );

    livePhase = LiveVoicePhase.listening;
    liveStatusHint = 'Seni dinliyorum...';
    liveTranscript = '';
    notifyListeners();

    var spoken = '';
    var usedWavStt = false;

    if (usesWavCaptureStt) {
      final wavTurn = await _captureAndTranscribeTurnWav(generation);
      if (!_ownsLiveTurn(generation)) return;
      if (wavTurn.permissionDenied) {
        await _endLiveTurns(_micPermissionText);
        return;
      }
      if (wavTurn.available) {
        usedWavStt = true;
        spoken = wavTurn.text;
      }
    }

    if (!usedWavStt) {
      await _endLiveTurns('Mikrofon başlatılamadı');
      return;
    }

    if (!liveLoopActive) return;
    orbAmplitude = 0.0;

    if (spoken.isEmpty) {
      if (liveStatusHint.startsWith('Sesin kayıtlı profil')) {
        // Ignore a different speaker without ending the owner's live session,
        // but never loop silently: after three rejections explain and stop.
        _liveSpeakerRejects++;
        _liveLog('ses kimliği reddetti ($_liveSpeakerRejects/3)');
        if (_liveSpeakerRejects < 3) {
          await _runLiveTurn();
          return;
        }
        _liveSpeakerRejects = 0;
        await _endLiveTurns(
          'Sesin üç kez kayıtlı ses profiliyle eşleşmedi. Ayarlar → Ses '
          'profili bölümünden profili yeniden kaydet ya da ses filtresini kapat.',
        );
        return;
      }
      if (liveStatusHint.startsWith('Konuşma duyulmadı')) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (_ownsLiveTurn(generation)) unawaited(_runLiveTurn());
        return;
      }
      await _endLiveTurns(
        liveStatusHint.startsWith('Konuşma duyulmadı') ||
                liveStatusHint.startsWith('Mikrofondan')
            ? liveStatusHint
            : 'Ses duyulmadı. Devam etmek için mikrofona dokun.',
      );
      return;
    }

    if (LocalCommandEngine.isAssistantExit(spoken)) {
      await closeAssistant();
      return;
    }
    final stopNorm = LocalCommandEngine.normalizeTr(
      LocalCommandEngine.stripEndPunct(spoken),
    );
    if (stopNorm == 'görüşürüz' ||
        stopNorm == 'teşekkürler jarvis' ||
        stopNorm == 'teşekkürler ege') {
      await stopLiveSession();
      liveAssistantReply = 'Anlaşıldı, bekleme moduna geçiyorum.';
      notifyListeners();
      return;
    }

    _liveSpeakerRejects = 0;
    await _processLivePrompt(spoken);
  }

  Future<void> captureCameraAndAskLive() async {
    final prevActive = liveLoopActive;
    final err = await pickImage(source: ImageSource.camera);
    if (err != null) {
      liveStatusHint = err;
      notifyListeners();
      return;
    }
    if (pendingAttachments.isEmpty) return;

    liveLoopActive = true;
    await sendRealtimeTextPrompt(
      'Kameramda gördüğün şeyi Türkçe, net ve kısa bir şekilde açıkla.',
    );
    if (!prevActive && !liveLoopActive) {
      notifyListeners();
    }
  }

  Future<void> _processLivePrompt(String prompt) async {
    final generation = _liveTurnGeneration;
    livePhase = LiveVoicePhase.thinking;
    liveStatusHint = 'Düşünüyorum...';
    liveAssistantReply = '';
    notifyListeners();

    final aiSw = Stopwatch()..start();
    await sendMessage(prompt, speakReply: false);
    _liveLog('yanıt geldi ms=${aiSw.elapsedMilliseconds}');
    if (!_ownsLiveTurn(generation)) return;

    final msgs = activeSession.messages;
    final reply = msgs.isNotEmpty && msgs.last.role == 'assistant'
        ? msgs.last.content
        : '';

    if (reply.trim().isEmpty) {
      await _endLiveTurns('Yanıt alınamadı');
      return;
    }

    liveAssistantReply = LocalCommandEngine.stripActionTags(reply);
    livePhase = LiveVoicePhase.thinking;
    liveStatusHint = 'Ses hazırlanıyor...';
    orbAmplitude = 0.55;
    notifyListeners();

    try {
      await _voice.speak(
        reply,
        rate: settings.ttsRate,
        pitch: settings.ttsPitch,
        settings: settings,
        httpClient: httpClient,
        onAudioStarted: () async {
          _liveLog('seslendirme başladı motor=${settings.ttsEngine}');
          if (!_ownsLiveTurn(generation)) return;
          livePhase = LiveVoicePhase.speaking;
          liveStatusHint = 'Konuşuyorum...';
          notifyListeners();
          await _startLiveDuplex(generation);
        },
      );
    } catch (_) {
      if (_ownsLiveTurn(generation)) {
        await _endLiveTurns(
          'Ses motoruna ulaşılamadı. Ayarlar → Seslendirme bölümünü kontrol et.',
        );
      }
      return;
    }

    if (!_ownsLiveTurn(generation)) return;
    if (_voice.lastError != null) {
      await _endLiveTurns('Seslendirme başarısız: ${_voice.lastError}');
      return;
    }
    orbAmplitude = 0.0;
    if (_duplexCapture != null) {
      // Preserve an interrupted utterance; otherwise give the microphone back
      // to the preferred phone recognizer for the next ordinary turn.
      if (settings.sttMode == 'system' &&
          !SpeakerIdentity.instance.enabled &&
          !_duplexInterrupted) {
        final capture = _duplexCapture;
        _duplexCapture = null;
        DeviceBridge.onDuplexEvent = null;
        await DeviceBridge.stopDuplexCapture();
        if (capture != null && !capture.isCompleted) capture.complete(null);
      } else {
        await DeviceBridge.duplexPlaybackEnded(_duplexToken);
      }
    }
    if (!_ownsLiveTurn(generation)) return;
    // Biriken arka plan iş duyurularını mikrofon açılmadan önce oku.
    while (_pendingLiveAnnouncements.isNotEmpty && _ownsLiveTurn(generation)) {
      final text = _pendingLiveAnnouncements.removeAt(0);
      liveStatusHint = 'Konuşuyorum...';
      notifyListeners();
      try {
        await _voice.speak(
          text,
          rate: settings.ttsRate,
          pitch: settings.ttsPitch,
          settings: settings,
          httpClient: httpClient,
        );
      } catch (_) {}
    }
    if (!_ownsLiveTurn(generation)) return;
    if (liveLoopActive) {
      await _runLiveTurn();
    } else {
      livePhase = LiveVoicePhase.idle;
      notifyListeners();
    }
  }

  // -------------------- STUDIO --------------------

  Future<({bool ok, String text})> _runOneShotAi(String prompt) async {
    final userMsg = JarvisMessage(
      id: LocalCommandEngine.newId(),
      role: 'user',
      content: prompt,
      timestamp: DateTime.now(),
    );

    final buf = StringBuffer();
    String? errorMsg;

    try {
      await for (final ev in AiClient.streamChat(
        settings: settings,
        messages: [userMsg],
        client: httpClient,
      )) {
        if (ev.error != null) {
          errorMsg = ev.error;
        } else if (ev.fullText != null) {
          buf
            ..clear()
            ..write(ev.fullText!);
        }
      }
    } catch (e) {
      return (ok: false, text: 'Bağlantı hatası: $e');
    }

    if (errorMsg != null && buf.isEmpty) {
      return (ok: false, text: errorMsg);
    }
    return (
      ok: buf.isNotEmpty,
      text: LocalCommandEngine.stripActionTags(buf.toString()).trim(),
    );
  }

  Future<({bool ok, StudyArtifact? artifact, String? error})> runStudioTask({
    required String kind,
    required String title,
    required String prompt,
  }) async {
    final res = await _runOneShotAi(prompt);
    if (!res.ok) {
      return (ok: false, artifact: null, error: res.text);
    }
    final artifact = StudyArtifact(
      id: LocalCommandEngine.newId(),
      kind: kind,
      title: title,
      content: res.text,
      createdAt: DateTime.now(),
    );
    studies.insert(0, artifact);
    await _storage.saveStudies(studies);
    notifyListeners();
    return (ok: true, artifact: artifact, error: null);
  }

  Future<ImageGenResult> generateStudioImage({
    required String modelId,
    required String prompt,
    String size = '1024x1024',
  }) async {
    return AiClient.generateImage(
      settings: settings,
      prompt: prompt,
      modelOverride: modelId,
      size: size,
      client: httpClient,
    );
  }

  Future<void> deleteStudy(String id) async {
    studies.removeWhere((s) => s.id == id);
    await _storage.saveStudies(studies);
    notifyListeners();
  }

  Future<void> transferStudyToChat(StudyArtifact study) async {
    final msg = JarvisMessage(
      id: LocalCommandEngine.newId(),
      role: 'assistant',
      content: '### ${study.title}\n\n${study.content}',
      timestamp: DateTime.now(),
      modelUsed: 'Stüdyo Çıktısı',
    );
    final updated = activeSession.copyWith(
      updatedAt: DateTime.now(),
      messages: [...activeSession.messages, msg],
    );
    _replaceSession(updated);
    await persistSessions();
    openTab(0);
  }

  void addCalcHistory(String expr, String result) {
    calcHistory.insert(0, (expr: expr, result: result));
    if (calcHistory.length > 25) {
      calcHistory.removeRange(25, calcHistory.length);
    }
    notifyListeners();
  }

  void clearCalcHistory() {
    calcHistory.clear();
    notifyListeners();
  }

  String buildGreetingHint() {
    final h = DateTime.now().hour;
    if (h < 6) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  double get activeOrbEnergy {
    if (livePhase == LiveVoicePhase.speaking) {
      return math.max(0.45, orbAmplitude);
    }
    if (livePhase == LiveVoicePhase.listening) {
      return math.max(0.2, orbAmplitude);
    }
    if (isStreaming || livePhase == LiveVoicePhase.thinking) return 0.65;
    return 0.0;
  }

  @override
  void dispose() {
    googleWorkspace.dispose();
    microsoftWorkspace.dispose();
    _vaultDebounce?.cancel();
    _disposed = true;
    whisperCancelRequested = true;
    _dictationGeneration++;
    _dictationWatchdog?.cancel();
    if (_phoneDictationActive) unawaited(DeviceBridge.cancelPhoneSpeech());
    liveLoopActive = false;
    final hadLiveCapture = _liveCapture != null;
    _invalidateLiveTurn();
    if (hadLiveCapture) unawaited(DeviceBridge.cancelMicCapture());
    _ticker?.cancel();
    _downloadPoller?.cancel();
    _activeStreamSub?.cancel();
    DeviceBridge.setMicCallbacks();
    DeviceBridge.setLiveAudioCallbacks();
    unawaited(DeviceBridge.stopLivePcmMic());
    unawaited(DeviceBridge.closeLiveAudioStream());
    unawaited(_voice.dispose());
    musicPoller?.cancel();
    works.removeListener(_onWorksChanged);
    super.dispose();
  }
}
