import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/asistan_models.dart';
import '../ui/animations_3d.dart';
import '../ui/theme_asistan.dart';
import 'ai_engine.dart';
import 'document_builder.dart';
import 'scraper_downloader_service.dart';
import 'download_queue.dart';

class AsistanController extends ChangeNotifier {
  AsistanController() {
    engine = AiEngine(nativeCaller: invokeNative);
    _setupMethodChannel();
  }

  static const MethodChannel _channel = MethodChannel(
    'com.mehmetderin.asistan/native',
  );

  late final AiEngine engine;
  final DownloadQueue downloadQueue = DownloadQueue();
  String downloadDraftUrl = '';
  String downloadQueueError = '';

  // Navigation & UI State
  int currentTabIndex = 0; // 0: Sohbet, 1: Canlı Ses, 2: Konsey & Araştırma, 3: Atölye & Görsel, 4: Merkez
  AsistanThemePreset themePreset = AsistanThemePreset.presets.first;
  String wallpaperAsset = 'assets/images/bg_higgsfield_technology.png';
  double wallpaperDim = 0.62;

  // AI & Proxy Configuration
  List<AiModelInfo> availableModels = List.from(AiModelInfo.defaultCatalog);
  String selectedModelId = 'auto';
  WorkMode activeWorkMode = WorkMode.auto;
  ProxyAuthStatus proxyAuthStatus = ProxyAuthStatus.checking;
  String proxyStatusMessage =
      'Siri CLIProxy (127.0.0.1:8317) kontrol ediliyor...';
  bool proxyOnline = false;
  bool isGenerating = false;

  // Claude Code Reading & Persona State
  String activePersonaId = 'claude_code';
  double chatFontSize = 15.5;
  bool wideReadingMode = true;

  // Background & Live Voice Assistant State
  bool backgroundServiceEnabled = true;
  bool backgroundLiveMode = true;
  bool liveSessionActive = false;
  LiveBrainMode liveBrainMode = LiveBrainMode.geminiLive;
  bool wakeWordEnabled = false;
  bool handsFreeVoiceLoop = true;
  Timer? _listenTimer;
  int _voiceEpoch = 0;
  bool _disposed = false;
  bool _startingListen = false;
  String voiceError = '';

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    downloadQueue.dispose();
    _disposed = true;
    _voiceEpoch++;
    _listenTimer?.cancel();
    _channel.setMethodCallHandler(null);
    unawaited(invokeNative('stopListening'));
    unawaited(invokeNative('stopTts'));
    super.dispose();
  }

  void setHandsFreeVoiceLoop(bool enabled) {
    handsFreeVoiceLoop = enabled;
    if (!enabled) _listenTimer?.cancel();
    unawaited(_savePreferences());
    notifyListeners();
  }

  bool autoReadReplies = false;
  VoicePersona selectedPersona = VoicePersona.presets.first;

  OrbActivityState orbState = OrbActivityState.idle;
  double voiceAudioLevel = 0.0;
  String livePartialTranscript = '';
  String lastVoiceReply =
      'Merhaba! Mikrofon düğmesine dokunarak konuşabilirsiniz. Yanıtlar seçtiğiniz proxy modelinden alınır ve telefon tarafından seslendirilir.';

  // Chat Threads & Attachments
  List<ChatThread> threads = [];
  String activeThreadId = '';
  List<AttachmentItem> pendingAttachments = [];
  String threadSearchQuery = '';

  // Studio / Canvas State
  String canvasTitle = 'Asistan Çalışma Tuvali';
  String canvasContent = '''# Asistan AI Stüdyo & Tuval (v3.0)

Bu çalışma alanında üretilen **kodları**, **raporları**, **tabloları** veya **makaleleri** canlı olarak düzenleyebilir ve tek dokunuşla gerçek **PDF**, **Word (DOCX)**, **Excel (XLSX)** veya **PowerPoint (PPTX)** belgesine dönüştürebilirsiniz.

## Örnek Veri Tablosu (Excel Çıktısına Uygun)
Modül | Yetenek | Durum
Siri & Google Asistan | Canlı Ses, Fener, Alarm, Ayarlar | Aktif
ChatGPT + Gemini + Claude | Çoklu Model Konseyi & Sentez | Aktif
Derin Araştırma | Canlı Web Kaynakları [1] [2] | Aktif
Ofis & Görsel Atölyesi | PDF, DOCX, XLSX, PPTX, PNG | Aktif''';
  String canvasFormat = 'pdf';

  // Artifacts, Memory, Reminders, Inbox, MCP, Device Status
  List<GeneratedArtifact> artifacts = [];
  List<MemoryFact> memories = [];
  List<ReminderItem> reminders = [];
  List<SharedInboxItem> sharedInbox = [];
  List<McpServerConfig> mcpServers = [];
  DeviceStatusSnapshot deviceStatus = const DeviceStatusSnapshot();

  // Universal Web Scraper, Media Search & Bulk Downloader State
  WebScrapeResult? lastScrapeResult;
  bool isScraping = false;
  String scrapeMediaFilter = 'all'; // all, image, video, audio, document
  bool isBulkDownloading = false;
  int bulkCompletedCount = 0;
  int bulkTotalCount = 0;
  String lastDownloadStatus =
      'Tüm oluşturulan ve indirilen dosyalar otomatik olarak telefonunuzun "İndirilenler / Asistan" klasörüne kaydedilir.';

  ChatThread get activeThread {
    if (threads.isEmpty) {
      final initial = _createWelcomeThread();
      threads = [initial];
      activeThreadId = initial.id;
    }
    return threads.firstWhere(
      (t) => t.id == activeThreadId,
      orElse: () => threads.first,
    );
  }

  AiModelInfo get selectedModelInfo {
    return availableModels.firstWhere(
      (m) => m.id == selectedModelId,
      orElse: () => AiModelInfo.defaultCatalog.first,
    );
  }

  Future<void> initialize({bool skipNativeAndNetwork = false}) async {
    if (!skipNativeAndNetwork) {
      await _loadPreferences();
    }
    if (threads.isEmpty) {
      final welcome = _createWelcomeThread();
      threads = [welcome];
      activeThreadId = welcome.id;
    }
    notifyListeners();

    if (!skipNativeAndNetwork) {
      unawaited(_postInitSync());
    }
  }

  Future<void> _postInitSync() async {
    try {
      await downloadQueue.initialize();
    } catch (_) {
      downloadQueueError = 'İndirme kuyruğu yüklenemedi.';
      notifyListeners();
    }
    await refreshDeviceStatus();
    if (backgroundServiceEnabled) {
      await syncBackgroundService();
    }
    // 1. Recover CLIProxy key & URL from legacy native storage or clipboard
    final recovered = await invokeNative('recoverLegacyProxyConfig');
    if (recovered is Map) {
      final recUrl = recovered['proxyUrl']?.toString().trim() ?? '';
      final recKey = recovered['apiKey']?.toString().trim() ?? '';
      final clipKey = recovered['clipboardKey']?.toString().trim() ?? '';
      if (recUrl.isNotEmpty && engine.baseUrl == 'http://127.0.0.1:8317') {
        engine.baseUrl = recUrl;
      }
      final candidateKey = recKey.isNotEmpty ? recKey : clipKey;
      if (candidateKey.isNotEmpty &&
          (engine.apiKey.isEmpty || engine.apiKey == 'sk-cliproxy-local')) {
        engine.apiKey = candidateKey;
        await invokeNative('saveNativeProxyKey', {
          'key': candidateKey,
          'url': engine.baseUrl,
        });
        await _savePreferences();
      }
    }

    final launchPayload = await invokeNative('consumeLaunchPayload');
    if (launchPayload is Map) {
      _handleIncomingPayload(Map<String, dynamic>.from(launchPayload));
    }
    await refreshProxyAndModels();

    // If still needsKey (401) and native recovery found a different key, try it automatically
    if (proxyAuthStatus == ProxyAuthStatus.needsKey && recovered is Map) {
      final recKey = recovered['apiKey']?.toString().trim() ?? '';
      final clipKey = recovered['clipboardKey']?.toString().trim() ?? '';
      final altKey = (clipKey.isNotEmpty && clipKey != engine.apiKey)
          ? clipKey
          : (recKey.isNotEmpty && recKey != engine.apiKey ? recKey : '');
      if (altKey.isNotEmpty) {
        engine.apiKey = altKey;
        await invokeNative('saveNativeProxyKey', {
          'key': altKey,
          'url': engine.baseUrl,
        });
        await _savePreferences();
        await refreshProxyAndModels();
      }
    }
  }

  void _setupMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      final map = call.arguments is Map
          ? Map<String, dynamic>.from(call.arguments as Map)
          : <String, dynamic>{};

      switch (call.method) {
        case 'onClipboardProxyKey':
          final clipKey = map['key']?.toString().trim() ?? '';
          if (clipKey.isNotEmpty &&
              (proxyAuthStatus != ProxyAuthStatus.connected ||
                  engine.apiKey.isEmpty ||
                  engine.apiKey == 'sk-cliproxy-local')) {
            engine.apiKey = clipKey;
            await invokeNative('saveNativeProxyKey', {
              'key': clipKey,
              'url': engine.baseUrl,
            });
            await _savePreferences();
            await refreshProxyAndModels();
          }
          break;

        case 'onSpeechState':
          if (!liveSessionActive) break;
          final st = map['state']?.toString() ?? 'idle';
          if (st == 'listening' || st == 'speaking') {
            orbState = OrbActivityState.listening;
          } else if (st == 'processing') {
            orbState = OrbActivityState.thinking;
          }
          notifyListeners();
          break;

        case 'onSpeechRms':
          voiceAudioLevel = ((map['rms'] as num?)?.toDouble() ?? 0.05).clamp(
            0.0,
            1.0,
          );
          notifyListeners();
          break;

        case 'onSpeechPartial':
          if (!liveSessionActive) break;
          final txt = map['text']?.toString() ?? '';
          if (txt.isNotEmpty) {
            livePartialTranscript = txt;
            notifyListeners();
          }
          break;

        case 'onSpeechResult':
          if (!liveSessionActive || isGenerating) break;
          final txt = map['text']?.toString().trim() ?? '';
          voiceAudioLevel = 0.0;
          livePartialTranscript = txt;
          if (txt.isNotEmpty) {
            await _handleRecognizedSpeech(txt);
          } else {
            orbState = OrbActivityState.idle;
            notifyListeners();
            _scheduleContinuousLiveListenIfActive(delayMs: 550);
          }
          break;

        case 'onSpeechError':
          if (!liveSessionActive) break;
          voiceAudioLevel = 0.0;
          if (orbState != OrbActivityState.speaking && !isGenerating) {
            orbState = OrbActivityState.idle;
          }
          notifyListeners();
          final errCode = (map['code'] as num?)?.toInt() ?? 0;
          voiceError =
              map['message']?.toString() ?? 'Ses tanıma başlatılamadı.';
          if (errCode == 6 || errCode == 7) {
            _scheduleContinuousLiveListenIfActive(delayMs: 900);
          } else {
            liveSessionActive = false;
            _listenTimer?.cancel();
          }
          notifyListeners();
          break;

        case 'onTtsStart':
          if (orbState != OrbActivityState.speaking) break;
          orbState = OrbActivityState.speaking;
          voiceAudioLevel = 0.65;
          notifyListeners();
          break;

        case 'onTtsDone':
          if (orbState != OrbActivityState.speaking) break;
          if (map['error'] == true) {
            voiceError = 'Seslendirme tamamlanamadı. Yeniden deneyebilirsiniz.';
            liveSessionActive = false;
          }
          voiceAudioLevel = 0.0;
          orbState = OrbActivityState.idle;
          notifyListeners();
          _scheduleContinuousLiveListenIfActive(delayMs: 420);
          break;

        case 'onLaunchPayload':
          _handleIncomingPayload(map);
          break;

        case 'onBackgroundAction':
          final action = map['action']?.toString() ?? '';
          if (action == 'voice_listen') {
            currentTabIndex = 1;
            liveSessionActive = true;
            notifyListeners();
            await startVoiceListening();
          } else if (action == 'stop_tts') {
            await stopSpeechAndListening();
          }
          break;

        case 'onReminderTriggered':
          final title = map['title']?.toString() ?? 'Hatırlatıcı';
          final body = map['body']?.toString() ?? '';
          lastVoiceReply = 'Hatırlatıcı: $title — $body';
          notifyListeners();
          break;
      }
    });
  }

  void _scheduleContinuousLiveListenIfActive({int delayMs = 600}) {
    _listenTimer?.cancel();
    if (_disposed || !liveSessionActive || !handsFreeVoiceLoop) return;
    if (!backgroundLiveMode && currentTabIndex != 1 && !wakeWordEnabled) return;
    final epoch = _voiceEpoch;
    _listenTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!_disposed &&
          epoch == _voiceEpoch &&
          liveSessionActive &&
          handsFreeVoiceLoop &&
          !isGenerating &&
          orbState == OrbActivityState.idle) {
        unawaited(startVoiceListening(playTone: false));
      }
    });
  }

  Future<dynamic> invokeNative(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      return await _channel.invokeMethod(method, args);
    } catch (_) {
      return null;
    }
  }

  void _handleIncomingPayload(Map<String, dynamic> payload) {
    final type = payload['type']?.toString() ?? '';
    if (type == 'assist_voice') {
      currentTabIndex = 1;
      liveSessionActive = true;
      notifyListeners();
      if (payload['autoListen'] == true) {
        startVoiceListening();
      }
    } else if (type == 'new_chat') {
      createNewThread();
      currentTabIndex = 0;
      notifyListeners();
    } else if (type == 'share') {
      final sharedText = payload['text']?.toString().trim() ?? '';
      final sharedUri = Uri.tryParse(sharedText);
      if (sharedUri != null &&
          ['http', 'https'].contains(sharedUri.scheme) &&
          sharedUri.host.isNotEmpty &&
          !sharedText.contains(RegExp(r'\s'))) {
        downloadDraftUrl = sharedText;
        currentTabIndex = 2;
        notifyListeners();
        return;
      }
      final text = payload['text']?.toString() ?? '';
      final subject = payload['subject']?.toString() ?? 'Paylaşılan İçerik';
      final rawFiles = (payload['files'] as List?) ?? const [];
      final files = rawFiles
          .whereType<Map>()
          .map(
            (f) => AttachmentItem(
              name: f['name']?.toString() ?? 'dosya',
              path: f['path']?.toString() ?? '',
              mimeType: f['mimeType']?.toString() ?? 'application/octet-stream',
              sizeBytes: (f['size'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();

      final inboxItem = SharedInboxItem(
        id: 'in_${DateTime.now().millisecondsSinceEpoch}',
        title: subject.isEmpty ? 'Gelen Kutusu Paylaşımı' : subject,
        text: text,
        files: files,
        receivedAt: DateTime.now(),
      );
      sharedInbox.insert(0, inboxItem);
      if (files.isNotEmpty) {
        pendingAttachments.addAll(files);
      }
      _savePreferences();
      notifyListeners();
      if (text.isNotEmpty) {
        sendMessage('Paylaşılan bu içeriği incele ve özetle:\n$text');
      }
    }
  }

  // ─── LIVE VOICE (GEMINI LIVE / CHATGPT VOICE / CLAUDE LIVE / SIRI) ───────

  Future<void> toggleLiveSession() async {
    if (liveSessionActive ||
        orbState == OrbActivityState.listening ||
        orbState == OrbActivityState.speaking) {
      await stopSpeechAndListening();
    } else {
      liveSessionActive = true;
      if (backgroundLiveMode && backgroundServiceEnabled) {
        await syncBackgroundService();
      }
      await startVoiceListening(playTone: true);
    }
  }

  String? voiceModelFor(LiveBrainMode mode) {
    if (mode == LiveBrainMode.siriDevice) return 'auto';
    bool matches(String id) {
      final name = id.toLowerCase();
      return switch (mode) {
        LiveBrainMode.geminiLive => name.contains('gemini'),
        LiveBrainMode.chatgptVoice =>
          name.contains('gpt') || name.contains('codex'),
        LiveBrainMode.claudeLive => name.contains('claude'),
        LiveBrainMode.siriDevice => true,
      };
    }

    final ids = engine.liveProxyModelIds.where(matches).toList();
    if (ids.contains(mode.preferredModelId)) return mode.preferredModelId;
    return ids.isEmpty ? null : ids.first;
  }

  void setLiveBrainMode(LiveBrainMode mode) {
    liveBrainMode = mode;
    _savePreferences();
    if (backgroundServiceEnabled) {
      syncBackgroundService();
    }
    notifyListeners();
  }

  void toggleBackgroundLiveMode(bool enabled) {
    backgroundLiveMode = enabled;
    if (enabled && !backgroundServiceEnabled) {
      backgroundServiceEnabled = true;
    }
    syncBackgroundService();
    _savePreferences();
    notifyListeners();
  }

  Future<void> startVoiceListening({bool playTone = true}) async {
    if (_disposed ||
        _startingListen ||
        isGenerating ||
        orbState == OrbActivityState.listening) {
      return;
    }
    _startingListen = true;
    _listenTimer?.cancel();
    final epoch = ++_voiceEpoch;
    voiceError = '';
    await invokeNative('stopTts');
    if (_disposed || epoch != _voiceEpoch) {
      _startingListen = false;
      return;
    }
    if (playTone) {
      unawaited(invokeNative('playEarcon', {'type': 'start'}));
    }
    liveSessionActive = true;
    livePartialTranscript = '';
    orbState = OrbActivityState.listening;
    notifyListeners();
    final ok = await invokeNative('startListening', {
      'locale': 'tr-TR',
      'partial': true,
    });
    _startingListen = false;
    if (_disposed || epoch != _voiceEpoch) return;
    if (ok != true) {
      liveSessionActive = false;
      voiceError = 'Mikrofon açılamadı. Mikrofon iznini ve ses tanıma hizmetini kontrol edin.';
      orbState = OrbActivityState.idle;
      notifyListeners();
    }
  }

  Future<void> stopSpeechAndListening() async {
    liveSessionActive = false;
    wakeWordEnabled = false;
    engine.cancelPendingPhoneCommand();
    _voiceEpoch++;
    _listenTimer?.cancel();
    await invokeNative('stopListening');
    await invokeNative('stopTts');
    orbState = OrbActivityState.idle;
    voiceAudioLevel = 0.0;
    notifyListeners();
  }

  Future<void> interruptSpeechAndListen() async {
    await invokeNative('stopTts');
    liveSessionActive = true;
    await startVoiceListening(playTone: true);
  }

  Future<void> _handleRecognizedSpeech(String spokenText) async {
    var cleaned = spokenText.trim();
    final lower = cleaned.toLowerCase();

    // Stop command in voice
    if (lower == 'dur' ||
        lower == 'sustur' ||
        lower == 'canlı modu kapat' ||
        lower == 'dinlemeyi durdur') {
      await stopSpeechAndListening();
      return;
    }

    if (wakeWordEnabled) {
      for (final prefix in [
        'hey asistan',
        'merhaba asistan',
        'alo asistan',
        'hey siri',
      ]) {
        if (lower.startsWith(prefix)) {
          cleaned = cleaned.substring(prefix.length).trim();
          break;
        }
      }
      if (cleaned.isEmpty) {
        cleaned = 'Seni dinliyorum, nasıl yardımcı olabilirim?';
        await speakText(cleaned);
        return;
      }
    }
    await sendMessage(cleaned, fromVoice: true);
  }

  Future<void> speakText(String text) async {
    if (_disposed) return;
    final epoch = ++_voiceEpoch;
    _listenTimer?.cancel();
    await invokeNative('stopListening');
    if (_disposed || epoch != _voiceEpoch) return;
    final clean = _stripMarkdownForSpeech(text);
    if (clean.isEmpty) return;

    orbState = OrbActivityState.speaking;
    voiceAudioLevel = 0.6;
    notifyListeners();

    // Try neural speech from CLIProxy first if online
    if (proxyOnline) {
      final audioBytes = await engine.synthesizeNeuralSpeech(
        text: clean.length > 600 ? clean.substring(0, 600) : clean,
        voiceId: selectedPersona.id,
        speed: selectedPersona.rate,
      );
      if (_disposed || epoch != _voiceEpoch) return;
      if (audioBytes != null) {
        final played = await invokeNative('playAudioBytes', {
          'bytes': audioBytes,
          'ext': 'mp3',
        });
        if (played == true) return;
      }
    }

    // Fallback to native Android Turkish TextToSpeech
    if (_disposed || epoch != _voiceEpoch) return;
    final spoken = await invokeNative('speakTts', {
      'text': clean.length > 900 ? clean.substring(0, 900) : clean,
      'rate': selectedPersona.rate,
      'pitch': selectedPersona.pitch,
    });
    if (_disposed || epoch != _voiceEpoch) return;
    if (spoken != true) {
      voiceError = 'Seslendirme başlatılamadı. Telefonun Türkçe metin okuma ayarlarını kontrol edin.';
      liveSessionActive = false;
      orbState = OrbActivityState.idle;
      voiceAudioLevel = 0;
      notifyListeners();
    }
  }

  String _stripMarkdownForSpeech(String md) {
    return md
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' kod bloğu hazırlandı. ')
        .replaceAll(RegExp(r'[#*`_~>|]'), ' ')
        .replaceAll(RegExp(r'\[(\d+)\]'), '')
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ─── CHAT & MULTIMODAL MESSAGE DISPATCH ──────────────────────────────────

  Future<void> sendMessage(
    String rawText, {
    bool fromVoice = false,
    WorkMode? overrideMode,
    String? overrideModelId,
  }) async {
    final text = rawText.trim();
    if (text.isEmpty && pendingAttachments.isEmpty) return;
    if (isGenerating) return;

    final voiceEpoch = _voiceEpoch;
    final mode = overrideMode ?? (fromVoice ? WorkMode.voice : activeWorkMode);
    final effectiveModel =
        overrideModelId ??
        (fromVoice
            ? voiceModelFor(liveBrainMode) ?? liveBrainMode.preferredModelId
            : selectedModelId);
    final currentAttachments = List<AttachmentItem>.from(pendingAttachments);
    pendingAttachments.clear();

    final userMsg = ChatMessage(
      id: 'u_${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      text: text,
      timestamp: DateTime.now(),
      modelUsed: effectiveModel,
      workMode: mode,
      attachments: currentAttachments,
    );

    final thread = activeThread;
    final updatedMessages = [...thread.messages, userMsg];
    final newTitle = thread.messages.length <= 1 && text.isNotEmpty
        ? (text.length > 38 ? '${text.substring(0, 38)}...' : text)
        : thread.title;

    _replaceThread(
      thread.copyWith(
        title: newTitle,
        updatedAt: DateTime.now(),
        messages: updatedMessages,
      ),
    );

    isGenerating = true;
    orbState = OrbActivityState.thinking;
    notifyListeners();

    try {
      String enrichedPrompt = text;
      if (currentAttachments.isNotEmpty) {
        final attDesc = currentAttachments
            .map((a) => '${a.name} (${a.mimeType})')
            .join(', ');
        enrichedPrompt = '$text\n[Eklenen Dosyalar: $attDesc]';
      }

      // Check if user wants Web Scraping / Bulk Media Download / Audio File Download directly in Chat
      final lowerText = text.toLowerCase();
      final extraArtifacts = <GeneratedArtifact>[];
      final extraTraces = <ToolCallTrace>[];

      final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
      final wantsScrapeOrBulk =
          urlMatch != null ||
          RegExp(
            r'(kazı|scrape|toplu indir|bulk indir|resim indir|resimleri indir|video indir|videoları indir|ses indir|müzik indir|mp3 indir)',
          ).hasMatch(lowerText);

      if (wantsScrapeOrBulk) {
        final sw = Stopwatch()..start();
        final targetInput = urlMatch != null
            ? urlMatch.group(0)!
            : text
                  .replaceAll(
                    RegExp(
                      r'(kazı|scrape|toplu indir|bulk indir|resim indir|resimleri indir|video indir|videoları indir|ses indir|müzik indir|mp3 indir|bana|lütfen)',
                      caseSensitive: false,
                    ),
                    '',
                  )
                  .trim();
        final filter =
            lowerText.contains('ses') ||
                lowerText.contains('müzik') ||
                lowerText.contains('mp3')
            ? 'audio'
            : (lowerText.contains('video')
                  ? 'video'
                  : (lowerText.contains('resim') || lowerText.contains('foto')
                        ? 'image'
                        : 'all'));
        final scrapeRes = await ScraperDownloaderService.scrapeOrSearch(
          targetInput.isEmpty ? text : targetInput,
          mediaFilter: filter,
        );
        lastScrapeResult = scrapeRes;
        sw.stop();

        // Automatically download top 4 matching items directly into Download/Asistan
        for (final item in scrapeRes.items.take(4)) {
          final dlArt = await _downloadScrapedItemInternal(item);
          if (dlArt != null) {
            extraArtifacts.add(dlArt);
          }
        }

        extraTraces.add(
          ToolCallTrace(
            name: 'webKazimaVeIndirici',
            title:
                'Web Kazıma & Toplu Medya İndirici (${scrapeRes.items.length} Dosya Bulundu)',
            inputSummary: targetInput.isEmpty ? text : targetInput,
            outputSummary:
                '${extraArtifacts.length} dosya otomatik olarak İndirilenler/Asistan klasörüne indirildi. Tümünü görmek için "İndir & Kazı" sekmesini açabilirsiniz.',
            durationMs: sw.elapsedMilliseconds,
          ),
        );

        if (scrapeRes.cleanText.isNotEmpty) {
          enrichedPrompt =
              '$enrichedPrompt\n\n[WEB KAZIMA & MEDYA SONUÇLARI (${scrapeRes.items.length} medya bulundu, ${extraArtifacts.length} tanesi İndirilenler/Asistan klasörüne indirildi)]:\n${scrapeRes.cleanText.length > 2500 ? scrapeRes.cleanText.substring(0, 2500) : scrapeRes.cleanText}';
        }
      }

      final outcome = await engine.processUserTurn(
        prompt: enrichedPrompt,
        mode: mode,
        selectedModel: effectiveModel,
        history: thread.messages,
        memories: memories,
        mcpServers: mcpServers,
        personaId: activePersonaId,
        onReminderCreated: (rem) {
          reminders.insert(0, rem);
        },
        onMemoryAdded: (fact) {
          memories.insert(0, fact);
        },
      );

      proxyAuthStatus = engine.lastAuthStatus;
      proxyOnline = proxyAuthStatus == ProxyAuthStatus.connected;

      // Also check if user asked for an audio file ("ses dosyası", "ses kaydı indir", "mp3 oluştur", "wav indir")
      if (lowerText.contains('ses dosyası') ||
          lowerText.contains('ses olarak indir') ||
          lowerText.contains('ses kaydı oluştur') ||
          lowerText.contains('wav oluştur')) {
        final audioArt = await createAndDownloadAudioFile(
          outcome.replyText,
          title: newTitle,
        );
        if (audioArt != null) {
          extraArtifacts.add(audioArt);
        }
      }

      // Auto-save all generated office/image artifacts to Android public Downloads/Asistan
      final savedOutcomeArtifacts = <GeneratedArtifact>[];
      for (final art in outcome.artifacts) {
        final savedArt = await _saveArtifactToPublicDownloads(art);
        savedOutcomeArtifacts.add(savedArt);
      }

      final allTurnArtifacts = [...extraArtifacts, ...savedOutcomeArtifacts];
      final allTurnTraces = [...extraTraces, ...outcome.toolTraces];

      if (allTurnArtifacts.isNotEmpty) {
        for (final a in allTurnArtifacts.reversed) {
          if (!artifacts.any((existing) => existing.id == a.id)) {
            artifacts.insert(0, a);
          }
        }
      }

      if (mode == WorkMode.canvas || outcome.replyText.contains('```')) {
        canvasTitle = newTitle;
        canvasContent = outcome.replyText;
      }

      final assistantMsg = ChatMessage(
        id: 'a_${DateTime.now().microsecondsSinceEpoch}',
        role: 'assistant',
        text: outcome.replyText,
        reasoningText: outcome.reasoningText,
        timestamp: DateTime.now(),
        modelUsed: outcome.modelUsed,
        workMode: mode,
        toolTraces: allTurnTraces,
        citations: outcome.citations,
        artifacts: allTurnArtifacts,
        arenaCandidates: outcome.arenaCandidates,
      );

      lastVoiceReply = outcome.replyText;
      _replaceThread(
        threads
            .firstWhere((t) => t.id == thread.id, orElse: () => thread)
            .copyWith(
              updatedAt: DateTime.now(),
              messages: [...updatedMessages, assistantMsg],
            ),
      );
      isGenerating = false;
      orbState = OrbActivityState.idle;
      await _savePreferences();
      notifyListeners();

      if (!_disposed &&
          voiceEpoch == _voiceEpoch &&
          (!fromVoice || liveSessionActive) &&
          (fromVoice || autoReadReplies || mode == WorkMode.voice)) {
        await speakText(outcome.replyText);
      }
    } catch (e) {
      if (fromVoice) {
        voiceError =
            'Yanıt alınamadı. Proxy bağlantısını kontrol edip yeniden deneyin.';
        liveSessionActive = false;
      }
      final errMsg = ChatMessage(
        id: 'err_${DateTime.now().microsecondsSinceEpoch}',
        role: 'assistant',
        text: 'Yanıt alınamadı. Bağlantınızı ve seçilen modelin kullanılabilirliğini kontrol edip yeniden deneyin.',
        timestamp: DateTime.now(),
        modelUsed: effectiveModel,
        workMode: mode,
        isError: true,
      );
      _replaceThread(
        threads
            .firstWhere((t) => t.id == thread.id, orElse: () => thread)
            .copyWith(
              updatedAt: DateTime.now(),
              messages: [...updatedMessages, errMsg],
            ),
      );
      isGenerating = false;
      orbState = OrbActivityState.idle;
      notifyListeners();
    }
  }

  Future<void> regenerateMessageWithModel(
    ChatMessage targetMsg,
    String newModelId,
  ) async {
    if (isGenerating) return;
    selectedModelId = newModelId;
    final msgs = activeThread.messages;
    final idx = msgs.indexWhere((m) => m.id == targetMsg.id);
    String promptToRun = '';
    if (idx > 0) {
      for (int i = idx - 1; i >= 0; i--) {
        if (msgs[i].role == 'user' && msgs[i].text.trim().isNotEmpty) {
          promptToRun = msgs[i].text;
          break;
        }
      }
    }
    if (promptToRun.isEmpty && targetMsg.role == 'user') {
      promptToRun = targetMsg.text;
    }
    if (promptToRun.isEmpty) return;
    await sendMessage(promptToRun, overrideModelId: newModelId);
  }

  // ─── PUBLIC DOWNLOADS AUTO-SAVER & 1-TAP OFFICE / AUDIO SUITE ────────────

  Future<GeneratedArtifact> _saveArtifactToPublicDownloads(
    GeneratedArtifact artifact,
  ) async {
    try {
      final f = File(artifact.filePath);
      if (!await f.exists()) return artifact;
      final bytes = await f.readAsBytes();
      final ext = artifact.format.toLowerCase();
      final subFolder = switch (ext) {
        'png' || 'jpg' || 'jpeg' || 'webp' || 'gif' => 'Asistan/Resimler',
        'mp3' || 'wav' || 'm4a' || 'ogg' => 'Asistan/Sesler',
        'mp4' || 'webm' || 'mov' => 'Asistan/Videolar',
        _ => 'Asistan/Belgeler',
      };
      final fileName = f.uri.pathSegments.isNotEmpty
          ? f.uri.pathSegments.last
          : '${artifact.title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')}.$ext';

      final res = await invokeNative('saveToPublicDownloads', {
        'fileName': fileName,
        'subFolder': subFolder,
        'mimeType': artifact.mimeType,
        'bytes': bytes,
      });

      if (res is Map && res['ok'] == true) {
        final pubPath = res['path']?.toString() ?? artifact.filePath;
        final disp =
            res['displayPath']?.toString() ??
            'İndirilenler/$subFolder/$fileName';
        lastDownloadStatus = '✅ Kaydedildi: $disp';
        return GeneratedArtifact(
          id: artifact.id,
          title: artifact.title,
          filePath: pubPath,
          format: artifact.format,
          mimeType: artifact.mimeType,
          contentPreview: '📂 $disp\n${artifact.contentPreview}',
          createdAt: artifact.createdAt,
          sizeBytes: artifact.sizeBytes,
        );
      }
    } catch (_) {}
    return artifact;
  }

  Future<GeneratedArtifact> exportCanvasAsDocument({
    required String title,
    required String content,
    required String format,
  }) async {
    canvasTitle = title;
    canvasContent = content;
    canvasFormat = format;
    final rawArtifact = await DocumentBuilder.createOfficeDocument(
      title: title,
      content: content,
      format: format,
    );
    final artifact = await _saveArtifactToPublicDownloads(rawArtifact);
    artifacts.insert(0, artifact);
    await _savePreferences();
    notifyListeners();
    return artifact;
  }

  Future<List<GeneratedArtifact>> createAllOfficeFormatsPack({
    required String title,
    required String content,
  }) async {
    final formats = ['pdf', 'docx', 'xlsx', 'pptx', 'csv', 'html'];
    final created = <GeneratedArtifact>[];
    for (final fmt in formats) {
      final raw = await DocumentBuilder.createOfficeDocument(
        title: title,
        content: content,
        format: fmt,
      );
      final saved = await _saveArtifactToPublicDownloads(raw);
      created.add(saved);
      artifacts.insert(0, saved);
    }
    final audioArt = await createAndDownloadAudioFile(content, title: title);
    if (audioArt != null) {
      created.add(audioArt);
    }
    lastDownloadStatus =
        '✅ Tüm Ofis Paketi (${created.length} dosya: PDF, Word, Excel, Sunum, CSV, HTML ve Ses) İndirilenler/Asistan klasörüne kaydedildi!';
    await _savePreferences();
    notifyListeners();
    return created;
  }

  Future<GeneratedArtifact?> createAndDownloadAudioFile(
    String text, {
    String title = 'Asistan_Sesli_Okuma',
  }) async {
    final clean = _stripMarkdownForSpeech(text);
    if (clean.isEmpty) return null;

    // 1. Try Neural MP3 via CLIProxy first if connected
    if (proxyOnline) {
      final mp3Bytes = await engine.synthesizeNeuralSpeech(
        text: clean.length > 2500 ? clean.substring(0, 2500) : clean,
        voiceId: selectedPersona.id,
        speed: selectedPersona.rate,
      );
      if (mp3Bytes != null && mp3Bytes.isNotEmpty) {
        final safeTitle = title
            .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
            .trim();
        final stem = safeTitle.isEmpty
            ? 'Asistan_Ses'
            : (safeTitle.length > 32 ? safeTitle.substring(0, 32) : safeTitle);
        final fileName =
            '${stem}_${DateTime.now().millisecondsSinceEpoch % 100000}.mp3';
        final saveRes = await invokeNative('saveToPublicDownloads', {
          'fileName': fileName,
          'subFolder': 'Asistan/Sesler',
          'mimeType': 'audio/mpeg',
          'bytes': mp3Bytes,
        });
        if (saveRes is Map && saveRes['ok'] == true) {
          final path = saveRes['path']?.toString() ?? '';
          final disp =
              saveRes['displayPath']?.toString() ??
              'İndirilenler/Asistan/Sesler/$fileName';
          final art = GeneratedArtifact(
            id: 'aud_${DateTime.now().microsecondsSinceEpoch}',
            title: '$title (MP3 Ses)',
            filePath: path,
            format: 'mp3',
            mimeType: 'audio/mpeg',
            contentPreview: '🎵 $disp • Neural MP3 Ses Dosyası',
            createdAt: DateTime.now(),
            sizeBytes: mp3Bytes.length,
          );
          artifacts.insert(0, art);
          lastDownloadStatus = '✅ Ses dosyası indirildi: $disp';
          await _savePreferences();
          notifyListeners();
          return art;
        }
      }
    }

    // 2. Fallback to Android Native TTS synthesizeToFile (.wav)
    final res = await invokeNative('synthesizeTtsToFile', {
      'text': clean,
      'title': title,
      'rate': selectedPersona.rate,
      'pitch': selectedPersona.pitch,
    });
    if (res is Map && res['ok'] == true) {
      final path = res['path']?.toString() ?? '';
      final disp =
          res['displayPath']?.toString() ?? 'İndirilenler/Asistan/Sesler';
      final size = (res['sizeBytes'] as num?)?.toInt() ?? 0;
      final art = GeneratedArtifact(
        id: 'wav_${DateTime.now().microsecondsSinceEpoch}',
        title: '$title (WAV Ses)',
        filePath: path,
        format: 'wav',
        mimeType: 'audio/wav',
        contentPreview: '🎵 $disp • Türkçe Ses Dosyası',
        createdAt: DateTime.now(),
        sizeBytes: size,
      );
      artifacts.insert(0, art);
      lastDownloadStatus = '✅ Ses dosyası indirildi: $disp';
      await _savePreferences();
      notifyListeners();
      return art;
    }
    return null;
  }

  Future<GeneratedArtifact> createStudioImage({
    required String prompt,
    required String style,
  }) async {
    isGenerating = true;
    notifyListeners();
    try {
      final rawArtifact = await engine.generateImageWithProxyOrFallback(
        prompt: prompt,
        style: style,
      );
      final artifact = await _saveArtifactToPublicDownloads(rawArtifact);
      artifacts.insert(0, artifact);
      await _savePreferences();
      return artifact;
    } finally {
      isGenerating = false;
      notifyListeners();
    }
  }

  // ─── UNIVERSAL WEB SCRAPER & BULK DOWNLOADER METHODS ────────────────────

  Future<WebScrapeResult> runWebScrapeOrSearch(
    String input, {
    String? mediaFilter,
  }) async {
    if (mediaFilter != null) {
      scrapeMediaFilter = mediaFilter;
    }
    isScraping = true;
    lastDownloadStatus =
        '🔍 "$input" taranıyor ve medya dosyaları çıkarılıyor...';
    notifyListeners();

    try {
      final res = await ScraperDownloaderService.scrapeOrSearch(
        input,
        mediaFilter: scrapeMediaFilter,
      );
      lastScrapeResult = res;
      lastDownloadStatus =
          '✅ ${res.items.length} adet indirilebilir dosya bulundu (${res.countByType(ScrapedMediaType.image)} Resim, ${res.countByType(ScrapedMediaType.audio)} Ses, ${res.countByType(ScrapedMediaType.video)} Video, ${res.countByType(ScrapedMediaType.document)} Belge).';
      return res;
    } finally {
      isScraping = false;
      notifyListeners();
    }
  }

  void toggleScrapedItemSelection(ScrapedMediaItem item, bool selected) {
    item.selected = selected;
    notifyListeners();
  }

  void toggleSelectAllScrapedItems(
    bool selectAll, {
    ScrapedMediaType? filterType,
  }) {
    final res = lastScrapeResult;
    if (res == null) return;
    for (final item in res.items) {
      if (filterType == null || item.type == filterType) {
        item.selected = selectAll;
      }
    }
    notifyListeners();
  }

  Future<GeneratedArtifact?> _downloadScrapedItemInternal(
    ScrapedMediaItem item,
  ) async {
    return ScraperDownloaderService.downloadMediaItem(
      item: item,
      nativeSaver:
          ({
            required String fileName,
            required String subFolder,
            required String mimeType,
            required Uint8List bytes,
          }) async {
            final res = await invokeNative('saveToPublicDownloads', {
              'fileName': fileName,
              'subFolder': subFolder,
              'mimeType': mimeType,
              'bytes': bytes,
            });
            if (res is Map) {
              return Map<String, dynamic>.from(res);
            }
            return <String, dynamic>{'ok': false};
          },
    );
  }

  Future<GeneratedArtifact?> downloadSingleScrapedItem(
    ScrapedMediaItem item,
  ) async {
    lastDownloadStatus = '⏳ İndiriliyor: ${item.title}...';
    notifyListeners();
    final art = await _downloadScrapedItemInternal(item);
    if (art != null) {
      artifacts.insert(0, art);
      lastDownloadStatus =
          '✅ İndirildi: ${item.title} -> İndirilenler/${item.subFolder}';
      await _savePreferences();
    } else {
      lastDownloadStatus = '⚠️ İndirilemedi: ${item.title}';
    }
    notifyListeners();
    return art;
  }

  Future<int> bulkDownloadSelectedItems({ScrapedMediaType? filterType}) async {
    final res = lastScrapeResult;
    if (res == null || isBulkDownloading) return 0;

    final targets = res.items.where((e) {
      if (!e.selected) return false;
      if (filterType != null && e.type != filterType) return false;
      return true;
    }).toList();

    if (targets.isEmpty) {
      lastDownloadStatus = '⚠️ Lütfen indirilecek en az bir dosya seçin.';
      notifyListeners();
      return 0;
    }

    isBulkDownloading = true;
    bulkCompletedCount = 0;
    bulkTotalCount = targets.length;
    lastDownloadStatus =
        '📥 Toplu İndirme Başladı: 0 / $bulkTotalCount dosya indiriliyor...';
    notifyListeners();

    int successCount = 0;
    try {
      // Download in concurrent batches of 3 for fast & reliable bulk downloading
      const batchSize = 3;
      for (int i = 0; i < targets.length; i += batchSize) {
        final end = (i + batchSize < targets.length)
            ? i + batchSize
            : targets.length;
        final batch = targets.sublist(i, end);
        final batchResults = await Future.wait(
          batch.map((item) => _downloadScrapedItemInternal(item)),
        );
        for (final art in batchResults) {
          bulkCompletedCount++;
          if (art != null) {
            successCount++;
            artifacts.insert(0, art);
          }
        }
        lastDownloadStatus =
            '📥 Toplu İndirme: $bulkCompletedCount / $bulkTotalCount tamamlandı ($successCount başarılı -> İndirilenler/Asistan)';
        notifyListeners();
      }
      lastDownloadStatus =
          '🎉 Toplu İndirme Tamamlandı! $successCount / $bulkTotalCount dosya "İndirilenler/Asistan" klasörüne kaydedildi.';
      await _savePreferences();
    } finally {
      isBulkDownloading = false;
      notifyListeners();
    }
    return successCount;
  }

  Future<void> shareArtifact(GeneratedArtifact artifact) async {
    await invokeNative('shareFile', {
      'path': artifact.filePath,
      'title': artifact.title,
      'mimeType': artifact.mimeType,
      'text': '${artifact.title} — Asistan AI Studio ile oluşturuldu.',
    });
  }

  Future<void> openArtifact(GeneratedArtifact artifact) async {
    await invokeNative('openFile', {
      'path': artifact.filePath,
      'mimeType': artifact.mimeType,
    });
  }

  Future<void> saveArtifactToDevice(GeneratedArtifact artifact) async {
    final updated = await _saveArtifactToPublicDownloads(artifact);
    final idx = artifacts.indexWhere((a) => a.id == artifact.id);
    if (idx >= 0) {
      artifacts[idx] = updated;
    }
    notifyListeners();
  }

  Future<void> pickAttachments() async {
    final res = await invokeNative('pickFiles', {'allowMultiple': true});
    if (res is List) {
      for (final item in res) {
        if (item is Map) {
          pendingAttachments.add(
            AttachmentItem(
              name: item['name']?.toString() ?? 'dosya',
              path: item['path']?.toString() ?? '',
              mimeType:
                  item['mimeType']?.toString() ?? 'application/octet-stream',
              sizeBytes: (item['size'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }
      notifyListeners();
    }
  }

  // ─── THREAD, MEMORY, REMINDER, MCP & DEVICE HELPERS ──────────────────────

  void createNewThread() {
    final t = _createWelcomeThread();
    threads.insert(0, t);
    activeThreadId = t.id;
    _savePreferences();
    notifyListeners();
  }

  void selectThread(String id) {
    activeThreadId = id;
    notifyListeners();
  }

  void deleteThread(String id) {
    threads.removeWhere((t) => t.id == id);
    if (threads.isEmpty) {
      final t = _createWelcomeThread();
      threads = [t];
      activeThreadId = t.id;
    } else if (activeThreadId == id) {
      activeThreadId = threads.first.id;
    }
    _savePreferences();
    notifyListeners();
  }

  void _replaceThread(ChatThread updated) {
    final idx = threads.indexWhere((t) => t.id == updated.id);
    if (idx >= 0) {
      threads[idx] = updated;
    } else {
      threads.insert(0, updated);
    }
  }

  ChatThread _createWelcomeThread() {
    final now = DateTime.now();
    return ChatThread(
      id: 'th_${now.microsecondsSinceEpoch}',
      title: 'Yeni Sohbet',
      createdAt: now,
      updatedAt: now,
      messages: [
        ChatMessage(
          id: 'welcome_msg',
          role: 'assistant',
          timestamp: now,
          modelUsed: 'Asistan',
          workMode: WorkMode.auto,
          text: 'Merhaba! Bir soru sorabilir, mesaj yazabilir veya mikrofonla konuşabilirsiniz.',
        ),
      ],
    );
  }

  Future<void> refreshDeviceStatus() async {
    final raw = await invokeNative('getDeviceStatus');
    if (raw is Map) {
      deviceStatus = DeviceStatusSnapshot.fromMap(raw);
      notifyListeners();
    }
  }

  Future<void> executeQuickDeviceCommand(
    String action, {
    int? value,
    String? target,
  }) async {
    final res = await invokeNative('deviceAction', {
      'action': action,
      'value': ?value,
      'target': ?target,
    });
    if (res is Map && res['status'] is Map) {
      deviceStatus = DeviceStatusSnapshot.fromMap(res['status'] as Map);
    } else {
      await refreshDeviceStatus();
    }
    notifyListeners();
  }

  Future<void> syncBackgroundService() async {
    final liveSuffix = backgroundLiveMode
        ? ' • Canlı Mod: ${liveBrainMode.title}'
        : '';
    await invokeNative('updateBackgroundService', {
      'enabled': backgroundServiceEnabled,
      'title': 'Asistan AI v4.0 (${liveBrainMode.title})',
      'subtitle': 'Model: $selectedModelId$liveSuffix',
      'wakeWord': wakeWordEnabled || (liveSessionActive && backgroundLiveMode),
    });
  }

  Future<void> toggleBackgroundService(bool enabled) async {
    backgroundServiceEnabled = enabled;
    await syncBackgroundService();
    await _savePreferences();
    notifyListeners();
  }

  Future<void> toggleWakeWord(bool enabled) async {
    wakeWordEnabled = enabled;
    await syncBackgroundService();
    await _savePreferences();
    notifyListeners();
    if (enabled) {
      await startVoiceListening();
    }
  }

  Future<void> refreshProxyAndModels() async {
    final statusRes = await engine.checkProxyDetailedStatus();
    proxyAuthStatus = statusRes.status;
    proxyStatusMessage = statusRes.message;
    proxyOnline = statusRes.status == ProxyAuthStatus.connected;
    availableModels = statusRes.models;
    notifyListeners();
  }

  Future<bool> pasteKeyFromClipboardAndConnect() async {
    String clipText = '';
    final nativeClip = await invokeNative('getClipboardText');
    if (nativeClip is String && nativeClip.trim().isNotEmpty) {
      clipText = nativeClip.trim();
    } else {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      clipText = data?.text?.trim() ?? '';
    }
    if (clipText.isEmpty) return false;

    final keyMatch = RegExp(
      r'(sk-iphone-[A-Za-z0-9_-]{8,}|sk-[A-Za-z0-9_-]{10,})',
    ).firstMatch(clipText);
    final extractedKey = keyMatch != null ? keyMatch.group(0)! : clipText;

    engine.apiKey = extractedKey;
    await invokeNative('saveNativeProxyKey', {
      'key': extractedKey,
      'url': engine.baseUrl,
    });
    await _savePreferences();
    await refreshProxyAndModels();
    return proxyOnline;
  }

  Future<bool> openCliProxyApp() async {
    final res = await invokeNative('openCliProxyApp');
    return res == true;
  }

  void setPersona(String personaId) {
    activePersonaId = personaId;
    _savePreferences();
    notifyListeners();
  }

  void adjustFontSize(double delta) {
    chatFontSize = (chatFontSize + delta).clamp(13.0, 21.0);
    _savePreferences();
    notifyListeners();
  }

  void toggleWideReadingMode() {
    wideReadingMode = !wideReadingMode;
    _savePreferences();
    notifyListeners();
  }

  void setThemePreset(AsistanThemePreset preset) {
    themePreset = preset;
    wallpaperAsset = preset.defaultWallpaper;
    _savePreferences();
    notifyListeners();
  }

  void setWallpaper(String assetPath) {
    wallpaperAsset = assetPath;
    _savePreferences();
    notifyListeners();
  }

  void setWorkMode(WorkMode mode) {
    activeWorkMode = mode;
    notifyListeners();
  }

  void setSelectedModel(String modelId) {
    selectedModelId = modelId;
    if (backgroundServiceEnabled) {
      syncBackgroundService();
    }
    _savePreferences();
    notifyListeners();
  }

  void addMemoryFact(String category, String fact) {
    if (fact.trim().isEmpty) return;
    memories.insert(
      0,
      MemoryFact(
        id: 'mem_${DateTime.now().millisecondsSinceEpoch}',
        category: category,
        fact: fact.trim(),
        createdAt: DateTime.now(),
      ),
    );
    _savePreferences();
    notifyListeners();
  }

  void deleteMemoryFact(String id) {
    memories.removeWhere((m) => m.id == id);
    _savePreferences();
    notifyListeners();
  }

  Future<void> addReminder({
    required String title,
    required String body,
    required DateTime triggerAt,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch % 100000;
    await invokeNative('scheduleReminder', {
      'id': id,
      'title': title,
      'body': body,
      'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
    });
    reminders.insert(
      0,
      ReminderItem(id: id, title: title, body: body, triggerAt: triggerAt),
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> removeReminder(int id) async {
    await invokeNative('cancelReminder', {'id': id});
    reminders.removeWhere((r) => r.id == id);
    await _savePreferences();
    notifyListeners();
  }

  Future<void> addMcpServer({
    required String name,
    required String url,
    String authToken = '',
  }) async {
    final base = McpServerConfig(
      id: 'mcp_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      url: url.trim(),
      authToken: authToken.trim(),
    );
    final tools = await engine.discoverMcpServerTools(base);
    mcpServers.add(base.copyWith(tools: tools));
    await _savePreferences();
    notifyListeners();
  }

  void removeMcpServer(String id) {
    mcpServers.removeWhere((s) => s.id == id);
    _savePreferences();
    notifyListeners();
  }

  Future<void> updateServerConfig({
    required String proxyUrl,
    required String proxyKey,
    required String geminiKey,
  }) async {
    engine.baseUrl = proxyUrl.trim().isEmpty
        ? 'http://127.0.0.1:8317'
        : proxyUrl.trim();
    engine.apiKey = proxyKey.trim();
    engine.geminiDirectApiKey = geminiKey.trim();
    await invokeNative('saveNativeProxyKey', {
      'key': engine.apiKey,
      'url': engine.baseUrl,
    });
    await _savePreferences();
    await refreshProxyAndModels();
  }

  // ─── PERSISTENCE ─────────────────────────────────────────────────────────

  Future<File> _stateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/asistan_v3_state.json');
  }

  Future<void> _loadPreferences() async {
    try {
      final file = await _stateFile();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;

      themePreset = data['balanced_ui_v1'] == true
          ? AsistanThemePreset.fromId(data['theme_id']?.toString())
          : AsistanThemePreset.presets.first;
      wallpaperAsset =
          (data['balanced_ui_v1'] == true
              ? data['wallpaper_asset']?.toString()
              : null) ??
          themePreset.defaultWallpaper;
      wallpaperDim = (data['wallpaper_dim'] as num?)?.toDouble() ?? 0.62;
      selectedModelId = data['selected_model']?.toString() ?? 'auto';
      activePersonaId = data['persona_id']?.toString() ?? 'claude_code';
      chatFontSize = ((data['chat_font_size'] as num?)?.toDouble() ?? 15.5)
          .clamp(13.0, 21.0);
      wideReadingMode = data['wide_reading'] != false;
      liveBrainMode = LiveBrainMode.fromId(data['live_brain_mode']?.toString());
      backgroundLiveMode = data['bg_live_mode'] != false;
      backgroundServiceEnabled = data['bg_service'] != false;
      wakeWordEnabled = data['wake_word'] == true;
      handsFreeVoiceLoop = data['hands_free'] != false;
      autoReadReplies = data['auto_read'] == true;

      engine.baseUrl = data['proxy_url']?.toString() ?? 'http://127.0.0.1:8317';
      final savedKey = data['proxy_key']?.toString() ?? '';
      engine.apiKey = savedKey == 'sk-cliproxy-local' ? '' : savedKey;
      engine.geminiDirectApiKey = data['gemini_key']?.toString() ?? '';

      final threadsList = data['threads'] as List?;
      if (threadsList != null && threadsList.isNotEmpty) {
        threads = threadsList
            .whereType<Map>()
            .map((e) => ChatThread.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (threads.isNotEmpty) {
          activeThreadId = threads.first.id;
        }
      }

      final memList = data['memories'] as List?;
      if (memList != null) {
        memories = memList
            .whereType<Map>()
            .map((e) => MemoryFact.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      final remList = data['reminders'] as List?;
      if (remList != null) {
        reminders = remList
            .whereType<Map>()
            .map((e) => ReminderItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      final artList = data['artifacts'] as List?;
      if (artList != null) {
        artifacts = artList
            .whereType<Map>()
            .map(
              (e) => GeneratedArtifact.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList();
      }

      final mcpList = data['mcp'] as List?;
      if (mcpList != null) {
        mcpServers = mcpList
            .whereType<Map>()
            .map((e) => McpServerConfig.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _savePreferences() async {
    try {
      final file = await _stateFile();
      final payload = <String, dynamic>{
        'theme_id': themePreset.id,
        'balanced_ui_v1': true,
        'wallpaper_asset': wallpaperAsset,
        'wallpaper_dim': wallpaperDim,
        'selected_model': selectedModelId,
        'persona_id': activePersonaId,
        'chat_font_size': chatFontSize,
        'wide_reading': wideReadingMode,
        'live_brain_mode': liveBrainMode.id,
        'bg_live_mode': backgroundLiveMode,
        'bg_service': backgroundServiceEnabled,
        'wake_word': wakeWordEnabled,
        'hands_free': handsFreeVoiceLoop,
        'auto_read': autoReadReplies,
        'proxy_url': engine.baseUrl,
        'proxy_key': engine.apiKey,
        'gemini_key': engine.geminiDirectApiKey,
        'threads': threads.take(25).map((e) => e.toJson()).toList(),
        'memories': memories.take(100).map((e) => e.toJson()).toList(),
        'reminders': reminders.take(50).map((e) => e.toJson()).toList(),
        'artifacts': artifacts.take(40).map((e) => e.toJson()).toList(),
        'mcp': mcpServers.map((e) => e.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }
}
