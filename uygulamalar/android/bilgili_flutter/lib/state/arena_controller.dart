import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../data/seed_extras.dart';
import '../models/quiz_models.dart';
import '../services/ai_gateway_service.dart';
import '../services/native_bridge.dart';
import '../services/voice_answer_resolver.dart';
import '../theme/arena_design.dart';

List<Map<String, dynamic>> _extractRawQuestionMaps(String rawJson) {
  final decoded = jsonDecode(rawJson);
  final List items;
  if (decoded is List) {
    items = decoded;
  } else if (decoded is Map && decoded['questions'] is List) {
    items = decoded['questions'] as List;
  } else {
    items = const [];
  }
  return items
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList(growable: false);
}

List<Question> _parseQuestionsInIsolate(String rawJson) {
  final maps = _extractRawQuestionMaps(rawJson);
  final parsed = <Question>[];
  for (var i = 0; i < maps.length; i++) {
    parsed.add(Question.fromJson(maps[i], fallbackIndex: 1000 + i));
  }
  return parsed;
}

List<Question> _parseMegaBankInIsolate(Uint8List gzBytes) {
  final rawBytes = GZipDecoder().decodeBytes(gzBytes);
  final text = utf8.decode(rawBytes, allowMalformed: true);
  final lines = const LineSplitter().convert(text);
  final parsed = <Question>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    final parts = line.split('\t');
    if (parts.length < 10) continue;
    final id = parts[0];
    final qText = parts[1];
    if (qText.isEmpty) continue;
    final opts = <String>[parts[2], parts[3], parts[4], parts[5]];
    final ans = (int.tryParse(parts[6]) ?? 0).clamp(0, 3);
    final exp = parts[7];
    final cat = Topic.fromLabel(parts[8]);
    final diff = Difficulty.fromLabel(parts[9]);
    final examStr = parts.length > 10 ? parts[10] : '';
    final lessonStr = parts.length > 11 ? parts[11] : '';
    parsed.add(
      Question(
        id: id,
        contentID: id,
        text: qText,
        options: opts,
        answer: ans,
        explanation: exp,
        category: cat,
        difficulty: diff,
        exam: examStr.isNotEmpty ? ExamKind.fromLabel(examStr) : null,
        lesson: lessonStr.isNotEmpty ? lessonStr : null,
        sourceModel: 'yerleşik-mega-100k',
      ),
    );
  }
  return parsed;
}

List<Question> _parseMegaVisualActivityBankInIsolate(Uint8List gzBytes) {
  final rawBytes = GZipDecoder().decodeBytes(gzBytes);
  final text = utf8.decode(rawBytes, allowMalformed: true);
  final lines = const LineSplitter().convert(text);
  final parsed = <Question>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    final parts = line.split('\t');
    if (parts.length < 14) continue;
    final id = parts[0];
    final qText = parts[1];
    if (qText.isEmpty) continue;
    final opts = <String>[parts[2], parts[3], parts[4], parts[5]];
    final ans = (int.tryParse(parts[6]) ?? 0).clamp(0, 3);
    final exp = parts[7];
    final cat = Topic.fromLabel(parts[8]);
    final diff = Difficulty.fromLabel(parts[9]);
    final examStr = parts[10];
    final lessonStr = parts[11];
    final kindTag = parts[12];
    final payload = parts[13];

    QuestionVisual? visual;
    QuestionActivity? activity;
    final p = payload.split('|');

    if (kindTag == 'V:barChart' || kindTag == 'V:lineChart') {
      if (p.length >= 5) {
        final vKind = kindTag == 'V:barChart' ? VisualKind.barChart : VisualKind.lineChart;
        final labels = p[3].split('~');
        final values = p[4].split('~').map((v) => double.tryParse(v) ?? 0.0).toList();
        visual = QuestionVisual(
          kind: vKind,
          title: p[0],
          summary: p[1],
          unit: p[2].isEmpty ? null : p[2],
          labels: labels,
          values: values,
        );
      }
    } else if (kindTag == 'V:table') {
      if (p.length >= 4) {
        final cols = p[2].split('~');
        final rows = p[3]
            .split('^')
            .where((r) => r.isNotEmpty)
            .map((r) => r.split('~'))
            .toList();
        visual = QuestionVisual(
          kind: VisualKind.table,
          title: p[0],
          summary: p[1],
          columns: cols,
          rows: rows,
        );
      }
    } else if (kindTag == 'V:diagram') {
      if (p.length >= 3) {
        final elems = <DiagramElement>[];
        for (final rawEl in p[2].split('^')) {
          if (rawEl.isEmpty) continue;
          final ep = rawEl.split(',');
          if (ep.length >= 3) {
            elems.add(
              DiagramElement(
                shape: ep[0],
                x: double.tryParse(ep[1]) ?? 50,
                y: double.tryParse(ep[2]) ?? 50,
                width: ep.length > 3 && ep[3].isNotEmpty ? double.tryParse(ep[3]) : null,
                height: ep.length > 4 && ep[4].isNotEmpty ? double.tryParse(ep[4]) : null,
                endX: ep.length > 5 && ep[5].isNotEmpty ? double.tryParse(ep[5]) : null,
                endY: ep.length > 6 && ep[6].isNotEmpty ? double.tryParse(ep[6]) : null,
                label: ep.length > 7 && ep[7].isNotEmpty ? ep[7] : null,
                color: ep.length > 8 && ep[8].isNotEmpty ? ep[8] : null,
              ),
            );
          }
        }
        visual = QuestionVisual(
          kind: VisualKind.diagram,
          title: p[0],
          summary: p[1],
          elements: elems,
        );
      }
    } else if (kindTag == 'V:image') {
      if (p.length >= 3) {
        visual = QuestionVisual(
          kind: VisualKind.image,
          title: p[0],
          summary: p[1],
          imageID: p[2],
        );
      }
    } else if (kindTag == 'A:listening' || kindTag == 'A:pronunciation') {
      if (p.length >= 3) {
        activity = QuestionActivity(
          kind: kindTag == 'A:listening' ? ActivityKind.listening : ActivityKind.pronunciation,
          title: p[0],
          language: p[1],
          transcript: p[2],
        );
      }
    } else if (kindTag == 'A:ordering') {
      if (p.length >= 3) {
        final items = p[1].split('~');
        final sol = p[2].split('~').map((s) => int.tryParse(s) ?? 0).toList();
        activity = QuestionActivity(
          kind: ActivityKind.ordering,
          title: p[0],
          items: items,
          solution: sol,
        );
      }
    } else if (kindTag == 'A:matching') {
      if (p.length >= 4) {
        final left = p[1].split('~');
        final right = p[2].split('~');
        final sol = p[3].split('~').map((s) => int.tryParse(s) ?? 0).toList();
        activity = QuestionActivity(
          kind: ActivityKind.matching,
          title: p[0],
          left: left,
          right: right,
          solution: sol,
        );
      }
    }

    parsed.add(
      Question(
        id: id,
        contentID: id,
        text: qText,
        options: opts,
        answer: ans,
        explanation: exp,
        category: cat,
        difficulty: diff,
        exam: examStr.isNotEmpty ? ExamKind.fromLabel(examStr) : null,
        lesson: lessonStr.isNotEmpty ? lessonStr : null,
        visual: visual,
        activity: activity,
        sourceModel: 'yerleşik-gorsel-etkinlik-50k',
      ),
    );
  }
  return parsed;
}

enum LiveVoicePhase {
  idle,
  speakingQuestion,
  listening,
  reviewing,
  speakingFeedback,
  paused,
  error,
}

class ActiveRound {
  final String id;
  final String title;
  final RoundSetup setup;
  final List<Question> questions;
  int currentIndex = 0;
  bool revealed = false;
  bool paused = false;
  bool pausedByOverlay = false;
  bool waitingStageBreak = false;
  bool finished = false;
  int remainingSeconds = 15;
  int totalTimerSeconds = 15;
  int questionElapsedSeconds = 0;
  int totalScore = 0;
  int streak = 0;
  int maxStreak = 0;
  bool jokerFiftyUsed = false;
  bool jokerTimeUsed = false;
  bool jokerSkipUsed = false;
  Set<int> hiddenOptions = {};
  final List<AnswerRecord> answers = [];
  final List<int> duelScores;
  final List<int> duelCorrects;

  ActiveRound({
    required this.id,
    required this.title,
    required this.setup,
    required this.questions,
  })  : duelScores = List<int>.filled(setup.duelPlayerNames.length, 0),
        duelCorrects = List<int>.filled(setup.duelPlayerNames.length, 0);

  Question get current => questions[currentIndex];
  bool get isDuel => setup.duelPlayerNames.length >= 2;
  int get activeDuelPlayerIndex =>
      isDuel ? (currentIndex % setup.duelPlayerNames.length) : 0;
  String get activeDuelPlayerName =>
      isDuel ? setup.duelPlayerNames[activeDuelPlayerIndex] : '';

  int get currentStageNumber {
    if (setup.mode != GameMode.stages) return 1;
    final third = max(1, (questions.length / 3).ceil());
    return ((currentIndex ~/ third) + 1).clamp(1, 3);
  }

  String get currentStageLabel {
    switch (currentStageNumber) {
      case 1:
        return '1. Etap · Isınma (20 sn)';
      case 2:
        return '2. Etap · Odak (15 sn)';
      default:
        return '3. Etap · Büyük Final (10 sn)';
    }
  }

  int stageSecondsForIndex(int idx) {
    final third = max(1, (questions.length / 3).ceil());
    final stage = ((idx ~/ third) + 1).clamp(1, 3);
    if (stage == 1) return 20;
    if (stage == 2) return 15;
    return 10;
  }
}

class ArenaBadgeInfo {
  final String id;
  final String title;
  final String description;
  final IconDataCompat iconKind;
  final bool unlocked;

  const ArenaBadgeInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.iconKind,
    required this.unlocked,
  });
}

enum IconDataCompat { spark, curious, flawless, master, collector, aiExplorer, voiceStar, duelKing }

class ArenaController extends ChangeNotifier {
  final bool persistToDisk;
  final Random _rng = Random();

  // Question Pool
  final List<Question> _allQuestions = [];
  final Set<String> _loadedIds = {};
  final Set<String> _poolKeys = {};
  final Map<Topic, int> _categoryCounts = {};
  int _visualCount = 0;
  int _activityCount = 0;
  bool isFullPoolLoaded = false;
  bool isLoadingPool = false;

  // User Progress & Collections
  int xp = 0;
  int dailyStreak = 1;
  String? lastPlayedDayKey;
  String? completedDailyChallengeDayKey;
  final Set<String> playedQuestionIds = {};
  final Set<String> reportedQuestionIds = {};
  final Map<String, int> categoryAnswered = {};
  final Map<String, int> categoryCorrect = {};
  final List<Question> savedBookmarks = [];
  final List<ReviewCard> reviewDeck = [];
  final List<QuestionPack> offlinePacks = [];
  final List<RoundSummary> history = [];
  List<StudyProfile> studyProfiles = [
    const StudyProfile(
      id: 'prof_tyt_mat',
      title: 'TYT Temel Matematik Kampı',
      exam: ExamKind.tyt,
      lesson: 'Temel Matematik',
      difficulty: Difficulty.medium,
      questionCount: 10,
    ),
    const StudyProfile(
      id: 'prof_kpss_gk',
      title: 'KPSS Tarih & Vatandaşlık',
      exam: ExamKind.kpss,
      lesson: 'Tarih',
      difficulty: Difficulty.medium,
      questionCount: 15,
    ),
    const StudyProfile(
      id: 'prof_lgs_fen',
      title: 'LGS Fen Bilimleri Hız',
      exam: ExamKind.lgs,
      lesson: 'Fen Bilimleri',
      difficulty: Difficulty.easy,
      questionCount: 10,
    ),
  ];

  // Undo import state
  String? lastImportedPackId;
  List<String> lastImportedQuestionIds = [];

  // Setup & Active Round
  RoundSetup setup = const RoundSetup();
  ActiveRound? activeRound;
  Timer? _roundTimer;

  // Live Voice & Speech State
  StreamSubscription<VoiceEvent>? _voiceSub;
  LiveVoicePhase livePhase = LiveVoicePhase.idle;
  String liveTranscript = '';
  String livePreview = '';
  String? liveError;
  double micLevel = 0.0;
  int liveReviewCountdown = 0;
  int _liveToken = 0;

  // AI & CLIProxyAPI State
  AiGatewayConfig aiConfig = const AiGatewayConfig();
  List<AiModelDescriptor> availableModels = List.of(AiGatewayService.builtInCatalog);
  final Map<String, ModelProbeStatus> modelHealth = {};
  bool isDiscoveringModels = false;
  bool isGeneratingAiQuestions = false;
  String aiGenerationStatus = '';
  int aiGeneratedRoundCount = 0;
  final Map<String, int> dailyGeneratedByCategory = {};
  String dailyPoolDayKey = _todayKey();

  // Visual, Audio & Accessibility Settings
  String wallpaperId = 'observatory';
  WallpaperClarity wallpaperClarity = WallpaperClarity.balanced;
  EffectIntensity effectIntensity = EffectIntensity.rich;
  bool menuMusicEnabled = false;
  bool gameMusicEnabled = true;
  double musicVolume = 0.32;
  bool sfxEnabled = true;
  bool hapticsEnabled = true;
  String ttsVoice = NativeBridge.defaultTtsVoice;
  double ttsSpeechRate = 1.02;
  int voiceReviewSeconds = 2;
  bool liveVoiceExplain = true;
  bool highContrast = false;
  double readingScale = 1.0;
  bool reduceMotion = false;

  ArenaController({this.persistToDisk = true}) {
    _voiceSub = NativeBridge.voiceEvents.listen(_onNativeVoiceEvent);
  }

  factory ArenaController.inMemoryForTest({List<Question>? seedQuestions}) {
    NativeBridge.testMode = true;
    final ctrl = ArenaController(persistToDisk: false);
    final seeds = seedQuestions ?? SeedExtras.buildExtraSeeds();
    ctrl._mergeQuestions(seeds);
    ctrl.isFullPoolLoaded = true;
    return ctrl;
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  int get level => (xp ~/ 250) + 1;
  int get xpInCurrentLevel => xp % 250;
  List<Question> get allQuestions => UnmodifiableListView(_allQuestions);
  int get totalPoolCount => _allQuestions.length;
  int get visualQuestionCount => _visualCount;
  int get activityQuestionCount => _activityCount;
  ArenaWallpaper get currentWallpaper => ArenaWallpapers.byId(wallpaperId);

  int countForTopic(Topic t) {
    if (t == Topic.mixed || t == Topic.custom) return _allQuestions.length;
    return _categoryCounts[t] ?? 0;
  }

  List<ReviewCard> get dueReviewCards {
    final now = DateTime.now();
    return reviewDeck.where((c) => !c.due.isAfter(now)).toList();
  }

  bool get isDailyChallengeDoneToday => completedDailyChallengeDayKey == _todayKey();

  Future<void> initialize() async {
    if (isLoadingPool) return;
    isLoadingPool = true;
    notifyListeners();

    // 1. Extra curated seeds immediately
    _mergeQuestions(SeedExtras.buildExtraSeeds());

    // 2. Load persisted state if enabled
    if (persistToDisk) {
      await _loadPersistedState();
    }

    // 3. Load 420 rich seed questions (visuals + activities) immediately
    try {
      final rawSeeds = await rootBundle.loadString('assets/sorular/tohumlar.json');
      final maps = _extractRawQuestionMaps(rawSeeds);
      final parsed = <Question>[];
      for (var i = 0; i < maps.length; i++) {
        parsed.add(Question.fromJson(maps[i], fallbackIndex: i));
      }
      _mergeQuestions(parsed);
      notifyListeners();
    } catch (_) {}

    // 4. Load 20,000 embedded + 100,000 mega bank + 50,000 visual/activity bank in background isolates
    try {
      final rawEmbeddedFuture = rootBundle.loadString('assets/sorular/gomulu-sorular.json');
      final rawMegaFuture = rootBundle.load('assets/sorular/mega-banka-100k.tsv.gz');
      final rawVisual50kFuture = rootBundle.load('assets/sorular/mega-gorsel-etkinlik-50k.tsv.gz');

      final rawEmbedded = await rawEmbeddedFuture;
      final parsed20k = await compute(_parseQuestionsInIsolate, rawEmbedded);
      _mergePreverifiedEmbeddedQuestions(parsed20k);
      notifyListeners();

      final rawMegaData = await rawMegaFuture;
      final gzBytes = rawMegaData.buffer.asUint8List(
        rawMegaData.offsetInBytes,
        rawMegaData.lengthInBytes,
      );
      final parsed100k = await compute(_parseMegaBankInIsolate, gzBytes);
      _mergePreverifiedEmbeddedQuestions(parsed100k);
      notifyListeners();

      final rawVisual50kData = await rawVisual50kFuture;
      final gzVisualBytes = rawVisual50kData.buffer.asUint8List(
        rawVisual50kData.offsetInBytes,
        rawVisual50kData.lengthInBytes,
      );
      final parsed50kVisual =
          await compute(_parseMegaVisualActivityBankInIsolate, gzVisualBytes);
      _mergePreverifiedEmbeddedQuestions(parsed50kVisual);
      _rebuildBuiltinQuestionBankPacks();
    } catch (_) {
      _rebuildBuiltinQuestionBankPacks();
    }

    isFullPoolLoaded = true;
    isLoadingPool = false;
    _syncBackgroundMusic();
    notifyListeners();

    // Soft non-blocking discovery of CLIProxy models in background
    unawaited(refreshLiveModels(silent: true));
  }

  void _mergeQuestions(Iterable<Question> incoming) {
    for (final q in incoming) {
      if (q.text.trim().isEmpty) continue;
      if (!_loadedIds.add(q.id)) continue;
      final key = q.poolKey;
      if (_poolKeys.add(key)) {
        _allQuestions.add(q);
        _categoryCounts[q.category] = (_categoryCounts[q.category] ?? 0) + 1;
        if (q.visual != null) _visualCount++;
        if (q.activity != null) _activityCount++;
      }
    }
  }

  void _mergePreverifiedEmbeddedQuestions(List<Question> incoming) {
    for (var i = 0; i < incoming.length; i++) {
      final q = incoming[i];
      if (_loadedIds.add(q.id)) {
        _allQuestions.add(q);
        _categoryCounts[q.category] = (_categoryCounts[q.category] ?? 0) + 1;
        if (q.visual != null) _visualCount++;
        if (q.activity != null) _activityCount++;
      }
    }
  }

  void _ensurePoolKeysPopulated() {
    if (_poolKeys.length >= _allQuestions.length) return;
    for (var i = 0; i < _allQuestions.length; i++) {
      _poolKeys.add(_allQuestions[i].poolKey);
    }
  }

  void _recomputePoolStats() {
    _categoryCounts.clear();
    _visualCount = 0;
    _activityCount = 0;
    for (final q in _allQuestions) {
      _categoryCounts[q.category] = (_categoryCounts[q.category] ?? 0) + 1;
      if (q.visual != null) _visualCount++;
      if (q.activity != null) _activityCount++;
    }
  }

  void _rebuildBuiltinQuestionBankPacks() {
    offlinePacks.removeWhere((p) => p.id.startsWith('builtin_sb_'));
    final tyt = <Question>[];
    final ayt = <Question>[];
    final kpssLgs = <Question>[];
    final bilimTek = <Question>[];
    final tarihCog = <Question>[];
    final kulturEdeb = <Question>[];
    final sanatMuzik = <Question>[];
    final sinemaSpor = <Question>[];
    final dogaDil = <Question>[];
    final gorselBank = <Question>[];
    final dinlemeTelaffuzBank = <Question>[];
    final siralamaEslestirmeBank = <Question>[];

    for (var i = 0; i < _allQuestions.length; i++) {
      final q = _allQuestions[i];
      if (q.visual != null) {
        gorselBank.add(q);
      }
      if (q.activity != null) {
        if (q.activity!.kind == ActivityKind.listening ||
            q.activity!.kind == ActivityKind.pronunciation) {
          dinlemeTelaffuzBank.add(q);
        } else {
          siralamaEslestirmeBank.add(q);
        }
      }
      final cid = q.contentID ?? q.id;
      if (!cid.startsWith('sb10k_') &&
          !cid.startsWith('mb100k_') &&
          !cid.startsWith('mv50k_')) {
        continue;
      }
      switch (q.category) {
        case Topic.exam:
          if (q.exam == ExamKind.tyt) {
            tyt.add(q);
          } else if (q.exam == ExamKind.ayt) {
            ayt.add(q);
          } else if (q.exam == ExamKind.kpss || q.exam == ExamKind.lgs) {
            kpssLgs.add(q);
          }
          break;
        case Topic.science:
        case Topic.technology:
          bilimTek.add(q);
          break;
        case Topic.history:
        case Topic.geography:
          tarihCog.add(q);
          break;
        case Topic.culture:
        case Topic.literature:
          kulturEdeb.add(q);
          break;
        case Topic.art:
        case Topic.music:
          sanatMuzik.add(q);
          break;
        case Topic.cinema:
        case Topic.sport:
          sinemaSpor.add(q);
          break;
        case Topic.nature:
        case Topic.language:
          dogaDil.add(q);
          break;
        case Topic.mixed:
        case Topic.custom:
          break;
      }
    }

    final now = DateTime(2026, 11, 14);
    final packEntries = <({String id, String title, List<String> tags, List<Question> qs})>[
      (
        id: 'builtin_sb_gorsel_etk',
        title: 'Görsel Grafik, Tablo & Şema Bankası',
        tags: const ['Görselli', 'Grafik', 'Tablo', 'Şema'],
        qs: gorselBank,
      ),
      (
        id: 'builtin_sb_dinleme_telaffuz',
        title: 'Dinleme & Çok Dilli Telaffuz Bankası',
        tags: const ['Dinleme', 'Telaffuz'],
        qs: dinlemeTelaffuzBank,
      ),
      (
        id: 'builtin_sb_siralama_eslestirme',
        title: 'Sıralama & Eşleştirme Etkinlik Bankası',
        tags: const ['Sıralama', 'Eşleştirme'],
        qs: siralamaEslestirmeBank,
      ),
      (
        id: 'builtin_sb_tyt',
        title: 'TYT Tam Soru Bankası',
        tags: const ['TYT', 'Sınav Hazırlık'],
        qs: tyt,
      ),
      (
        id: 'builtin_sb_ayt',
        title: 'AYT Alan Soru Bankası',
        tags: const ['AYT', 'Sınav Hazırlık'],
        qs: ayt,
      ),
      (
        id: 'builtin_sb_kpss_lgs',
        title: 'KPSS & LGS Kamp Soru Bankası',
        tags: const ['KPSS', 'LGS', 'Sınav Hazırlık'],
        qs: kpssLgs,
      ),
      (
        id: 'builtin_sb_bilim_tek',
        title: 'Bilim & Teknoloji Soru Bankası',
        tags: const ['Bilim', 'Teknoloji'],
        qs: bilimTek,
      ),
      (
        id: 'builtin_sb_tarih_cog',
        title: 'Tarih & Coğrafya Soru Bankası',
        tags: const ['Tarih', 'Coğrafya'],
        qs: tarihCog,
      ),
      (
        id: 'builtin_sb_kultur_edeb',
        title: 'Genel Kültür & Edebiyat Bankası',
        tags: const ['Genel Kültür', 'Edebiyat'],
        qs: kulturEdeb,
      ),
      (
        id: 'builtin_sb_sanat_muzik',
        title: 'Sanat & Müzik Soru Bankası',
        tags: const ['Sanat', 'Müzik'],
        qs: sanatMuzik,
      ),
      (
        id: 'builtin_sb_sinema_spor',
        title: 'Sinema, TV & Spor Soru Bankası',
        tags: const ['Sinema ve TV', 'Spor'],
        qs: sinemaSpor,
      ),
      (
        id: 'builtin_sb_doga_dil',
        title: 'Doğa & Yabancı Dil Soru Bankası',
        tags: const ['Doğa', 'Yabancı Dil'],
        qs: dogaDil,
      ),
    ];

    for (final entry in packEntries) {
      if (entry.qs.isNotEmpty) {
        offlinePacks.add(
          QuestionPack(
            id: entry.id,
            title: entry.title,
            createdAt: now,
            models: entry.tags,
            questions: entry.qs,
          ),
        );
      }
    }
  }

  // --- Wallpaper & Preferences ---
  void cycleWallpaper() {
    final list = ArenaWallpapers.catalog;
    final idx = list.indexWhere((w) => w.id == wallpaperId);
    wallpaperId = list[(idx + 1) % list.length].id;
    NativeBridge.playSfx('tick', enabled: sfxEnabled, haptics: hapticsEnabled, volume: 0.35);
    notifyListeners();
    unawaited(_savePersistedState());
  }

  void selectWallpaper(String id) {
    wallpaperId = id;
    notifyListeners();
    unawaited(_savePersistedState());
  }

  void updatePreferences({
    WallpaperClarity? clarity,
    EffectIntensity? intensity,
    bool? menuMusic,
    bool? gameMusic,
    double? volume,
    bool? sfx,
    bool? haptics,
    String? voice,
    double? speechRate,
    int? reviewSec,
    bool? liveExplain,
    bool? contrast,
    double? scale,
    bool? motion,
  }) {
    if (clarity != null) wallpaperClarity = clarity;
    if (intensity != null) effectIntensity = intensity;
    if (menuMusic != null) menuMusicEnabled = menuMusic;
    if (gameMusic != null) gameMusicEnabled = gameMusic;
    if (volume != null) musicVolume = volume;
    if (sfx != null) sfxEnabled = sfx;
    if (haptics != null) hapticsEnabled = haptics;
    if (voice != null && voice.trim().isNotEmpty) {
      ttsVoice = voice.trim();
      unawaited(NativeBridge.setTtsVoice(ttsVoice));
    }
    if (speechRate != null) ttsSpeechRate = speechRate;
    if (reviewSec != null) voiceReviewSeconds = reviewSec;
    if (liveExplain != null) liveVoiceExplain = liveExplain;
    if (contrast != null) highContrast = contrast;
    if (scale != null) readingScale = scale;
    if (motion != null) reduceMotion = motion;
    _syncBackgroundMusic();
    notifyListeners();
    unawaited(_savePersistedState());
  }

  void _syncBackgroundMusic() {
    if (activeRound != null && !activeRound!.finished && !activeRound!.paused) {
      if (gameMusicEnabled) {
        NativeBridge.setMusic('game', volume: musicVolume);
      } else {
        NativeBridge.setMusic(null);
      }
    } else {
      if (menuMusicEnabled) {
        NativeBridge.setMusic('menu', volume: musicVolume);
      } else {
        NativeBridge.setMusic(null);
      }
    }
  }

  void updateSetup(RoundSetup nextSetup) {
    setup = nextSetup;
    notifyListeners();
  }

  void applyPreset(String preset) {
    if (preset == 'kesif') {
      setup = setup.copyWith(
        mode: GameMode.training,
        questionCount: 8,
        difficulty: () => Difficulty.easy,
      );
    } else if (preset == 'kisa') {
      setup = setup.copyWith(
        mode: GameMode.classic,
        questionCount: 10,
        difficulty: () => null,
      );
    } else if (preset == 'maraton') {
      setup = setup.copyWith(
        mode: GameMode.stages,
        questionCount: 24,
        difficulty: () => null,
      );
    }
    notifyListeners();
  }

  // --- Sampling & Round Launchers ---
  List<Question> sampleQuestions(RoundSetup cfg, {int? seed}) {
    final rng = seed != null ? Random(seed) : _rng;
    final candidates = _allQuestions.where((q) {
      if (reportedQuestionIds.contains(q.id)) return false;
      if (cfg.topic != Topic.mixed && cfg.topic != Topic.custom) {
        if (cfg.topic == Topic.exam) {
          if (q.category != Topic.exam) return false;
          if (q.exam != null && q.exam != cfg.exam) return false;
          if (cfg.lesson != null &&
              cfg.lesson!.isNotEmpty &&
              q.lesson != null &&
              q.lesson != cfg.lesson) {
            return false;
          }
        } else if (q.category != cfg.topic) {
          return false;
        }
      }
      if (cfg.difficulty != null && q.difficulty != cfg.difficulty) {
        return false;
      }
      if (!q.matchesFormat(cfg.format)) return false;
      return true;
    }).toList();

    var pool = candidates;
    if (pool.length < cfg.questionCount) {
      // Relax difficulty/lesson constraint if narrow filter had few matches
      final relaxed = _allQuestions.where((q) {
        if (reportedQuestionIds.contains(q.id)) return false;
        if (!q.matchesFormat(cfg.format)) return false;
        if (cfg.topic != Topic.mixed && cfg.topic != Topic.custom && cfg.topic != Topic.exam) {
          return q.category == cfg.topic;
        }
        return true;
      }).toList();
      final existingIds = pool.map((e) => e.id).toSet();
      for (final extra in relaxed) {
        if (existingIds.add(extra.id)) pool.add(extra);
      }
    }
    if (pool.isEmpty) {
      pool = List<Question>.from(_allQuestions.take(20));
    }

    // Prioritize unplayed questions with fast random sampling on large pools
    return _pickRandomQuestions(pool, cfg.questionCount, rng);
  }

  List<Question> _pickRandomQuestions(List<Question> pool, int targetCount, Random rng) {
    if (pool.isEmpty) return const [];
    if (pool.length <= 600) {
      final unplayed = pool.where((q) => !playedQuestionIds.contains(q.id)).toList()..shuffle(rng);
      final played = pool.where((q) => playedQuestionIds.contains(q.id)).toList()..shuffle(rng);
      final combined = [...unplayed, ...played];
      return combined.take(targetCount).map((q) => q.shuffled(rng)).toList();
    }

    final picked = <Question>[];
    final pickedIds = <String>{};
    final maxAttempts = targetCount * 8;
    // Pass 1: random unplayed picks
    for (var i = 0; i < maxAttempts && picked.length < targetCount; i++) {
      final q = pool[rng.nextInt(pool.length)];
      if (!playedQuestionIds.contains(q.id) && pickedIds.add(q.id)) {
        picked.add(q.shuffled(rng));
      }
    }
    // Pass 2: random fallback from pool if needed
    for (var i = 0; i < maxAttempts && picked.length < targetCount; i++) {
      final q = pool[rng.nextInt(pool.length)];
      if (pickedIds.add(q.id)) {
        picked.add(q.shuffled(rng));
      }
    }
    if (picked.length < targetCount) {
      for (var i = 0; i < pool.length && picked.length < targetCount; i++) {
        final q = pool[i];
        if (pickedIds.add(q.id)) {
          picked.add(q.shuffled(rng));
        }
      }
    }
    return picked;
  }

  void startConfiguredRound({String? customTitle, RoundSetup? overrideSetup, int? seed}) {
    final cfg = overrideSetup ?? setup;
    final qs = sampleQuestions(cfg, seed: seed);
    if (qs.isEmpty) return;
    _beginRound(
      title: customTitle ??
          (cfg.duelPlayerNames.length >= 2
              ? 'Düello Arenası (${cfg.duelPlayerNames.length} Oyuncu)'
              : cfg.liveVoiceHost
                  ? 'Canlı Sesli Yarışma'
                  : '${cfg.topic.label} · ${cfg.mode.label}'),
      cfg: cfg,
      questions: qs,
    );
  }

  void startLiveVoiceQuiz() {
    final liveCfg = setup.copyWith(
      liveVoiceHost: true,
      mode: GameMode.classic,
      questionCount: 8,
    );
    startConfiguredRound(
      customTitle: 'Canlı Sesli Yarışma',
      overrideSetup: liveCfg,
    );
  }

  void startDailyChallenge() {
    final today = _todayKey();
    final seed = today.codeUnits.fold<int>(17, (acc, c) => acc * 31 + c);
    final dailyCfg = const RoundSetup(
      topic: Topic.mixed,
      mode: GameMode.classic,
      format: QuestionFormat.mixed,
      questionCount: 10,
    );
    startConfiguredRound(
      customTitle: 'Günün Turu ($today)',
      overrideSetup: dailyCfg,
      seed: seed,
    );
  }

  void startVisualAndActivityDiscovery() {
    final picked = <Question>[];
    final pickedIds = <String>{};
    final seenVisuals = <VisualKind>{};
    final seenActivities = <ActivityKind>{};
    final n = _allQuestions.length;

    if (n > 0) {
      // Fast random probes to gather a diverse mix of visual and activity kinds
      for (var attempt = 0; attempt < 600 && picked.length < 10; attempt++) {
        final q = _allQuestions[_rng.nextInt(n)];
        if (reportedQuestionIds.contains(q.id)) continue;
        if (q.visual == null && q.activity == null) continue;
        final isNewVisual = q.visual != null && seenVisuals.add(q.visual!.kind);
        final isNewAct = q.activity != null && seenActivities.add(q.activity!.kind);
        if ((isNewVisual || isNewAct || attempt > 240) && pickedIds.add(q.id)) {
          picked.add(q.shuffled(_rng));
        }
      }
      if (picked.length < 10) {
        for (var i = 0; i < n && picked.length < 10; i++) {
          final q = _allQuestions[i];
          if (!reportedQuestionIds.contains(q.id) &&
              (q.visual != null || q.activity != null) &&
              pickedIds.add(q.id)) {
            picked.add(q.shuffled(_rng));
          }
        }
      }
    }
    if (picked.isEmpty) return;
    _beginRound(
      title: 'Görsel & Etkinlik Keşif Turu',
      cfg: const RoundSetup(mode: GameMode.training, questionCount: 10),
      questions: picked,
    );
  }

  bool startSpacedRepetitionReview() {
    final due = dueReviewCards.isNotEmpty ? dueReviewCards : reviewDeck;
    if (due.isEmpty) return false;
    final qs = due.take(12).map((c) => c.question.shuffled(_rng)).toList();
    _beginRound(
      title: 'Aralıklı Tekrar Turu',
      cfg: RoundSetup(mode: GameMode.training, questionCount: qs.length),
      questions: qs,
    );
    return true;
  }

  void startDuelTournament(List<String> players, {Topic topic = Topic.mixed, int perPlayer = 3}) {
    final cleanNames = players.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (cleanNames.length < 2) return;
    final count = cleanNames.length * perPlayer;
    final cfg = RoundSetup(
      topic: topic,
      mode: GameMode.classic,
      format: QuestionFormat.text,
      questionCount: count,
      duelPlayerNames: cleanNames,
    );
    startConfiguredRound(
      customTitle: 'Düello Turnuvası (${cleanNames.join(" vs ")})',
      overrideSetup: cfg,
    );
  }

  void startPackRound(QuestionPack pack, {int? maxQuestions}) {
    if (pack.questions.isEmpty) return;
    final int targetCount = maxQuestions ??
        (pack.questions.length > 25 ? setup.questionCount.clamp(10, 30) : pack.questions.length);
    final qs = _pickRandomQuestions(pack.questions, targetCount, _rng);
    _beginRound(
      title: pack.title,
      cfg: RoundSetup(mode: setup.mode, questionCount: qs.length),
      questions: qs,
    );
  }

  void startStudyProfileRound(StudyProfile profile) {
    final cfg = RoundSetup(
      topic: Topic.exam,
      exam: profile.exam,
      lesson: profile.lesson,
      difficulty: profile.difficulty,
      mode: GameMode.classic,
      questionCount: profile.questionCount,
    );
    startConfiguredRound(customTitle: profile.title, overrideSetup: cfg);
  }

  void _beginRound({
    required String title,
    required RoundSetup cfg,
    required List<Question> questions,
  }) {
    _stopRoundTimer();
    stopLiveVoiceCycle();
    final round = ActiveRound(
      id: 'rnd_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      setup: cfg,
      questions: questions,
    );
    _configureTimersForQuestion(round, isFirstQuestion: true);
    activeRound = round;
    NativeBridge.playSfx('start', enabled: sfxEnabled, haptics: hapticsEnabled);
    _syncBackgroundMusic();
    _startRoundTimer();
    notifyListeners();

    if (cfg.liveVoiceHost) {
      unawaited(_runLiveVoiceForCurrentQuestion());
    }
  }

  void _configureTimersForQuestion(ActiveRound round, {required bool isFirstQuestion}) {
    round.questionElapsedSeconds = 0;
    round.hiddenOptions = {};
    switch (round.setup.mode) {
      case GameMode.training:
        round.totalTimerSeconds = 0;
        round.remainingSeconds = 0;
        break;
      case GameMode.classic:
        round.totalTimerSeconds = round.setup.liveVoiceHost ? 35 : 15;
        round.remainingSeconds = round.totalTimerSeconds;
        break;
      case GameMode.sprint:
        round.totalTimerSeconds = 8;
        round.remainingSeconds = 8;
        break;
      case GameMode.timed:
        if (isFirstQuestion) {
          round.totalTimerSeconds = round.setup.timedMinutes * 60;
          round.remainingSeconds = round.totalTimerSeconds;
        }
        break;
      case GameMode.stages:
        final sec = round.stageSecondsForIndex(round.currentIndex);
        round.totalTimerSeconds = sec;
        round.remainingSeconds = sec;
        break;
    }
  }

  void _startRoundTimer() {
    _roundTimer?.cancel();
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = activeRound;
      if (r == null || r.finished || r.paused || r.pausedByOverlay || r.waitingStageBreak || r.revealed) {
        return;
      }
      r.questionElapsedSeconds++;
      if (r.totalTimerSeconds <= 0) return;

      // In Live Voice mode while TTS is reading the question, hold countdown steady
      if (r.setup.liveVoiceHost && livePhase == LiveVoicePhase.speakingQuestion) {
        return;
      }

      if (r.remainingSeconds > 1) {
        r.remainingSeconds--;
        if (r.remainingSeconds <= 3) {
          NativeBridge.playSfx('tick', enabled: sfxEnabled, haptics: false, volume: 0.4);
        }
        notifyListeners();
      } else {
        r.remainingSeconds = 0;
        NativeBridge.playSfx('timeout', enabled: sfxEnabled, haptics: hapticsEnabled);
        if (r.setup.mode == GameMode.timed) {
          submitChoice(null);
          finishActiveRound();
        } else {
          submitChoice(null);
        }
      }
    });
  }

  void _stopRoundTimer() {
    _roundTimer?.cancel();
    _roundTimer = null;
  }

  void setOverlayPause(bool pause) {
    final r = activeRound;
    if (r == null) return;
    r.pausedByOverlay = pause;
    notifyListeners();
  }

  void togglePauseRound() {
    final r = activeRound;
    if (r == null || r.finished) return;
    r.paused = !r.paused;
    if (r.paused) {
      stopLiveVoiceCycle(keepPausedState: true);
    } else if (r.setup.liveVoiceHost && !r.revealed) {
      unawaited(_runLiveVoiceForCurrentQuestion());
    }
    _syncBackgroundMusic();
    notifyListeners();
  }

  // --- Jokers ---
  bool useFiftyFiftyJoker() {
    final r = activeRound;
    if (r == null ||
        r.revealed ||
        r.jokerFiftyUsed ||
        !r.setup.mode.allowsJokers ||
        r.current.isInteractiveSequence ||
        r.current.isPronunciation) {
      return false;
    }
    final wrongIndices = [0, 1, 2, 3]..remove(r.current.answer)..shuffle(_rng);
    r.hiddenOptions = wrongIndices.take(2).toSet();
    r.jokerFiftyUsed = true;
    NativeBridge.playSfx('joker', enabled: sfxEnabled, haptics: hapticsEnabled);
    notifyListeners();
    return true;
  }

  bool useExtraTimeJoker() {
    final r = activeRound;
    if (r == null ||
        r.revealed ||
        r.jokerTimeUsed ||
        !r.setup.mode.allowsJokers ||
        r.totalTimerSeconds <= 0) {
      return false;
    }
    r.remainingSeconds += 15;
    r.totalTimerSeconds = max(r.totalTimerSeconds, r.remainingSeconds);
    r.jokerTimeUsed = true;
    NativeBridge.playSfx('joker', enabled: sfxEnabled, haptics: hapticsEnabled);
    notifyListeners();
    return true;
  }

  bool useSkipJoker() {
    final r = activeRound;
    if (r == null || r.revealed || r.jokerSkipUsed || !r.setup.mode.allowsJokers) {
      return false;
    }
    r.jokerSkipUsed = true;
    NativeBridge.playSfx('joker', enabled: sfxEnabled, haptics: hapticsEnabled);
    if (r.currentIndex + 1 < r.questions.length) {
      r.currentIndex++;
      _configureTimersForQuestion(r, isFirstQuestion: false);
      notifyListeners();
      if (r.setup.liveVoiceHost) {
        unawaited(_runLiveVoiceForCurrentQuestion());
      }
    } else {
      finishActiveRound();
    }
    return true;
  }

  // --- Answer Submission ---
  void submitChoice(int? choiceIndex, {String? spokenTranscript}) {
    final r = activeRound;
    if (r == null || r.revealed || r.finished) return;
    final q = r.current;
    final isCorrect = choiceIndex != null && choiceIndex == q.answer;
    _commitAnswer(
      round: r,
      question: q,
      isCorrect: isCorrect,
      selectedOption: choiceIndex,
      spokenTranscript: spokenTranscript,
    );
  }

  void submitActivitySequence(List<int> sequence, {String? spokenTranscript}) {
    final r = activeRound;
    if (r == null || r.revealed || r.finished) return;
    final q = r.current;
    final act = q.activity;
    final isCorrect = act != null && act.matchesSequence(sequence);
    _commitAnswer(
      round: r,
      question: q,
      isCorrect: isCorrect,
      selectedOption: isCorrect ? q.answer : -1,
      submittedSequence: sequence,
      spokenTranscript: spokenTranscript,
    );
  }

  void _commitAnswer({
    required ActiveRound round,
    required Question question,
    required bool isCorrect,
    int? selectedOption,
    List<int>? submittedSequence,
    String? spokenTranscript,
  }) {
    round.revealed = true;
    playedQuestionIds.add(question.id);

    int points = 0;
    if (isCorrect) {
      round.streak++;
      round.maxStreak = max(round.maxStreak, round.streak);
      final speedBonus = round.totalTimerSeconds > 0
          ? ((round.remainingSeconds / max(1, round.totalTimerSeconds)) * 45).round()
          : 20;
      final streakBonus = min(round.streak * 15, 90);
      points = question.difficulty.basePoints + speedBonus + streakBonus;
      round.totalScore += points;
      if (round.isDuel) {
        round.duelScores[round.activeDuelPlayerIndex] += points;
        round.duelCorrects[round.activeDuelPlayerIndex]++;
      }
      NativeBridge.playSfx('correct', enabled: sfxEnabled, haptics: hapticsEnabled);
    } else {
      round.streak = 0;
      NativeBridge.playSfx('wrong', enabled: sfxEnabled, haptics: hapticsEnabled);
    }

    round.answers.add(
      AnswerRecord(
        question: question,
        selectedOption: selectedOption,
        submittedSequence: submittedSequence,
        spokenTranscript: spokenTranscript,
        correct: isCorrect,
        earnedPoints: points,
        elapsedSeconds: round.questionElapsedSeconds,
        duelPlayerIndex: round.isDuel ? round.activeDuelPlayerIndex : null,
      ),
    );

    // Update category mastery & Leitner review deck
    final catKey = question.category.label;
    categoryAnswered[catKey] = (categoryAnswered[catKey] ?? 0) + 1;
    if (isCorrect) {
      categoryCorrect[catKey] = (categoryCorrect[catKey] ?? 0) + 1;
    }
    _updateReviewDeck(question, isCorrect);
    notifyListeners();

    if (round.setup.liveVoiceHost) {
      unawaited(_speakLiveFeedbackAndAdvance());
    }
  }

  void _updateReviewDeck(Question question, bool wasCorrect) {
    final now = DateTime.now();
    final idx = reviewDeck.indexWhere((c) => c.question.poolKey == question.poolKey);
    if (idx >= 0) {
      reviewDeck[idx] = reviewDeck[idx].recordOutcome(wasCorrect, now);
    } else if (!wasCorrect) {
      reviewDeck.insert(
        0,
        ReviewCard(
          question: question,
          box: 0,
          attempts: 1,
          correct: 0,
          due: now.add(const Duration(minutes: 5)),
        ),
      );
    }
  }

  void nextQuestion() {
    final r = activeRound;
    if (r == null || r.finished) return;
    stopLiveVoiceCycle();

    if (r.currentIndex + 1 >= r.questions.length) {
      finishActiveRound();
      return;
    }

    final prevStage = r.currentStageNumber;
    r.currentIndex++;
    r.revealed = false;
    final nextStage = r.currentStageNumber;
    _configureTimersForQuestion(r, isFirstQuestion: false);

    if (r.setup.mode == GameMode.stages && nextStage > prevStage) {
      r.waitingStageBreak = true;
      NativeBridge.playSfx('stage', enabled: sfxEnabled, haptics: hapticsEnabled);
    }
    notifyListeners();

    if (!r.waitingStageBreak && r.setup.liveVoiceHost) {
      unawaited(_runLiveVoiceForCurrentQuestion());
    }
  }

  void continueFromStageBreak() {
    final r = activeRound;
    if (r == null) return;
    r.waitingStageBreak = false;
    notifyListeners();
    if (r.setup.liveVoiceHost) {
      unawaited(_runLiveVoiceForCurrentQuestion());
    }
  }

  void finishActiveRound() {
    final r = activeRound;
    if (r == null || r.finished) return;
    _stopRoundTimer();
    stopLiveVoiceCycle();
    r.finished = true;

    final correctCount = r.answers.where((a) => a.correct).length;
    int gainedXp = correctCount * 22 + (r.maxStreak * 8) + 25;
    if (r.title.startsWith('Günün Turu') && !isDailyChallengeDoneToday) {
      completedDailyChallengeDayKey = _todayKey();
      gainedXp += 120;
    }
    xp += gainedXp;

    final today = _todayKey();
    if (lastPlayedDayKey != today) {
      dailyStreak = lastPlayedDayKey == null ? 1 : dailyStreak + 1;
      lastPlayedDayKey = today;
    }

    final standings = <Map<String, dynamic>>[];
    if (r.isDuel) {
      for (var i = 0; i < r.setup.duelPlayerNames.length; i++) {
        standings.add({
          'name': r.setup.duelPlayerNames[i],
          'score': r.duelScores[i],
          'correct': r.duelCorrects[i],
        });
      }
      standings.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    }

    history.insert(
      0,
      RoundSummary(
        id: r.id,
        playedAt: DateTime.now(),
        title: r.title,
        topic: r.setup.topic,
        mode: r.setup.mode,
        totalQuestions: r.questions.length,
        correctCount: correctCount,
        totalScore: r.totalScore,
        xpGained: gainedXp,
        maxStreak: r.maxStreak,
        wasLiveVoice: r.setup.liveVoiceHost,
        duelStandings: standings,
      ),
    );
    if (history.length > 80) {
      history.removeRange(80, history.length);
    }

    NativeBridge.playSfx('victory', enabled: sfxEnabled, haptics: hapticsEnabled);
    _syncBackgroundMusic();
    notifyListeners();
    unawaited(_savePersistedState());
  }

  void exitRound() {
    _stopRoundTimer();
    stopLiveVoiceCycle();
    activeRound = null;
    _syncBackgroundMusic();
    notifyListeners();
  }

  // --- Live Voice Host & Single-Question Voice Answer ---
  Completer<VoiceEvent>? _pendingVoiceCompleter;

  void _onNativeVoiceEvent(VoiceEvent event) {
    if (event.type == 'rms') {
      micLevel = event.level;
      notifyListeners();
    } else if (event.type == 'partial') {
      liveTranscript = event.text;
      notifyListeners();
    } else if (event.type == 'result' || event.type == 'error') {
      micLevel = 0.0;
      if (event.type == 'result') liveTranscript = event.text;
      final c = _pendingVoiceCompleter;
      if (c != null && !c.isCompleted) {
        c.complete(event);
      }
      notifyListeners();
    }
  }

  Future<void> speakActivityAudio(Question q) async {
    final act = q.activity;
    if (act == null) return;
    final text = act.transcript ?? q.text;
    final lang = act.language ?? 'tr-TR';
    await NativeBridge.speak(
      text,
      language: lang,
      rate: lang.startsWith('tr') ? ttsSpeechRate : 0.92,
      awaitCompletion: false,
    );
  }

  Future<String?> listenOnceAndResolveCurrentQuestion({bool isPronunciation = false}) async {
    final r = activeRound;
    if (r == null || r.revealed) return null;
    final hasPerm = await NativeBridge.requestMicPermission();
    if (!hasPerm) {
      return 'Mikrofon izni verilmedi. Ayarlardan izin verebilirsin.';
    }
    await NativeBridge.stopSpeaking();
    liveTranscript = '';
    liveError = null;
    livePhase = LiveVoicePhase.listening;
    notifyListeners();

    final completer = Completer<VoiceEvent>();
    _pendingVoiceCompleter = completer;
    final lang = isPronunciation
        ? (r.current.activity?.language ?? 'en-US')
        : 'tr-TR';
    try {
      await NativeBridge.startListening(language: lang);
      final ev = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => const VoiceEvent(type: 'error', errorMessage: 'Dinleme zaman aşımına uğradı.'),
      );
      await NativeBridge.stopListening();
      livePhase = LiveVoicePhase.idle;
      if (ev.type == 'error') {
        liveError = ev.errorMessage ?? 'Ses anlaşılamadı.';
        notifyListeners();
        return liveError;
      }
      final cmd = VoiceAnswerResolver.detectCommand(ev.text);
      if (cmd == SpokenVoiceCommand.skip) {
        submitChoice(null, spokenTranscript: ev.text);
        return null;
      }
      if (cmd == SpokenVoiceCommand.pause) {
        togglePauseRound();
        return null;
      }
      final resolved = VoiceAnswerResolver.resolve(
        ev.text,
        r.current,
        alternatives: ev.alternatives,
      );
      if (resolved == null) {
        final msg = isPronunciation
            ? 'Söylenen: "${ev.text}" — hedef ifadeye yaklaşıyor, tekrar dene!'
            : '"${ev.text}" tek bir şıkla eşleşmedi. A, B, C, D veya seçeneği söyle.';
        liveError = msg;
        notifyListeners();
        return msg;
      }
      if (resolved.sequence != null) {
        submitActivitySequence(resolved.sequence!, spokenTranscript: ev.text);
      } else {
        submitChoice(resolved.choiceIndex, spokenTranscript: ev.text);
      }
      return null;
    } catch (e) {
      livePhase = LiveVoicePhase.idle;
      final msg = e.toString();
      liveError = msg;
      notifyListeners();
      return msg;
    }
  }

  Future<void> _runLiveVoiceForCurrentQuestion({bool skipReading = false}) async {
    final r = activeRound;
    if (r == null || !r.setup.liveVoiceHost || r.finished || r.paused || r.revealed) return;
    final token = ++_liveToken;
    liveError = null;
    liveTranscript = '';
    livePreview = '';

    if (!skipReading) {
      livePhase = LiveVoicePhase.speakingQuestion;
      notifyListeners();
      final narration = QuizNarration.buildQuestionSpeech(r.current, r.currentIndex + 1);
      await NativeBridge.speak(
        narration,
        language: 'tr-TR',
        rate: ttsSpeechRate,
        awaitCompletion: true,
      );
      if (_liveToken != token || activeRound != r || r.revealed || r.paused || r.finished) return;
    }

    final hasPerm = await NativeBridge.requestMicPermission();
    if (!hasPerm) {
      livePhase = LiveVoicePhase.error;
      liveError = 'Canlı sesli yarışma için mikrofon izni gerekli.';
      notifyListeners();
      return;
    }

    livePhase = LiveVoicePhase.listening;
    notifyListeners();
    final completer = Completer<VoiceEvent>();
    _pendingVoiceCompleter = completer;
    final lang = r.current.isPronunciation
        ? (r.current.activity?.language ?? 'en-US')
        : 'tr-TR';

    try {
      await NativeBridge.startListening(language: lang);
      final ev = await completer.future.timeout(
        const Duration(seconds: 11),
        onTimeout: () => const VoiceEvent(type: 'error', errorMessage: 'Yanıt duyulamadı.'),
      );
      await NativeBridge.stopListening();
      if (_liveToken != token || activeRound != r || r.revealed || r.paused || r.finished) return;

      if (ev.type == 'error') {
        livePhase = LiveVoicePhase.error;
        liveError = ev.errorMessage ?? 'Ses anlaşılamadı.';
        notifyListeners();
        return;
      }

      final cmd = VoiceAnswerResolver.detectCommand(ev.text);
      if (cmd == SpokenVoiceCommand.pause) {
        togglePauseRound();
        return;
      }
      if (cmd == SpokenVoiceCommand.repeatQuestion) {
        unawaited(_runLiveVoiceForCurrentQuestion(skipReading: false));
        return;
      }
      if (cmd == SpokenVoiceCommand.skip) {
        submitChoice(null, spokenTranscript: ev.text);
        return;
      }

      final resolved = VoiceAnswerResolver.resolve(
        ev.text,
        r.current,
        alternatives: ev.alternatives,
      );
      if (resolved == null) {
        livePhase = LiveVoicePhase.error;
        liveError = '"${ev.text}" anlaşılamadı. Tekrar söyle veya şıkka dokun.';
        notifyListeners();
        return;
      }

      if (resolved.choiceIndex != null) {
        const letters = ['A', 'B', 'C', 'D'];
        final idx = resolved.choiceIndex!;
        livePreview = '${letters[idx]} · ${r.current.options[idx]}';
      } else if (resolved.sequence != null) {
        livePreview = r.current.activity?.describeSequence(resolved.sequence!) ?? '';
      }

      livePhase = LiveVoicePhase.reviewing;
      for (var s = voiceReviewSeconds; s >= 1; s--) {
        liveReviewCountdown = s;
        notifyListeners();
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_liveToken != token || activeRound != r || r.revealed || r.paused || r.finished) return;
      }

      if (resolved.sequence != null) {
        submitActivitySequence(resolved.sequence!, spokenTranscript: ev.text);
      } else {
        submitChoice(resolved.choiceIndex, spokenTranscript: ev.text);
      }
    } catch (_) {
      if (_liveToken == token) {
        livePhase = LiveVoicePhase.error;
        liveError = 'Canlı ses bağlantısı kesildi. Mikrofon düğmesiyle yeniden dene.';
        notifyListeners();
      }
    }
  }

  Future<void> _speakLiveFeedbackAndAdvance() async {
    final r = activeRound;
    if (r == null || !r.setup.liveVoiceHost || r.answers.isEmpty) return;
    final token = ++_liveToken;
    livePhase = LiveVoicePhase.speakingFeedback;
    notifyListeners();

    final lastAns = r.answers.last;
    final speech = QuizNarration.buildFeedbackSpeech(
      r.current,
      correct: lastAns.correct,
      includeExplanation: liveVoiceExplain,
      isLast: r.currentIndex + 1 >= r.questions.length,
    );
    await NativeBridge.speak(
      speech,
      language: 'tr-TR',
      rate: ttsSpeechRate,
      awaitCompletion: true,
    );
    if (_liveToken != token || activeRound != r || r.paused || r.finished) return;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (_liveToken != token || activeRound != r || r.paused || r.finished) return;
    nextQuestion();
  }

  void retryLiveListening() {
    unawaited(_runLiveVoiceForCurrentQuestion(skipReading: true));
  }

  void stopLiveVoiceCycle({bool keepPausedState = false}) {
    _liveToken++;
    _pendingVoiceCompleter = null;
    micLevel = 0.0;
    liveReviewCountdown = 0;
    livePhase = keepPausedState ? LiveVoicePhase.paused : LiveVoicePhase.idle;
    unawaited(NativeBridge.stopSpeaking());
    unawaited(NativeBridge.cancelListening());
  }

  // --- Bookmarks, Reports & Study Profiles ---
  bool isBookmarked(Question q) => savedBookmarks.any((b) => b.poolKey == q.poolKey);

  void toggleBookmark(Question q) {
    final idx = savedBookmarks.indexWhere((b) => b.poolKey == q.poolKey);
    if (idx >= 0) {
      savedBookmarks.removeAt(idx);
    } else {
      savedBookmarks.insert(0, q);
    }
    NativeBridge.playSfx('tick', enabled: sfxEnabled, haptics: hapticsEnabled, volume: 0.35);
    notifyListeners();
    unawaited(_savePersistedState());
  }

  bool isReported(Question q) => reportedQuestionIds.contains(q.id);

  void toggleReportQuestion(Question q) {
    if (reportedQuestionIds.contains(q.id)) {
      reportedQuestionIds.remove(q.id);
    } else {
      reportedQuestionIds.add(q.id);
    }
    notifyListeners();
    unawaited(_savePersistedState());
  }

  void addStudyProfile(StudyProfile profile) {
    studyProfiles = [profile, ...studyProfiles];
    notifyListeners();
    unawaited(_savePersistedState());
  }

  void deleteStudyProfile(String id) {
    studyProfiles = studyProfiles.where((p) => p.id != id).toList();
    notifyListeners();
    unawaited(_savePersistedState());
  }

  // --- AI & CLIProxyAPI Actions ---
  void updateAiConfig(AiGatewayConfig next) {
    aiConfig = next;
    notifyListeners();
    unawaited(_savePersistedState());
  }

  void toggleTeamModel(String modelId) {
    final current = List<String>.from(aiConfig.teamModels);
    if (current.contains(modelId)) {
      if (current.length > 1) current.remove(modelId);
    } else {
      current.add(modelId);
    }
    updateAiConfig(aiConfig.copyWith(teamModels: current));
  }

  Future<int> refreshLiveModels({bool silent = false}) async {
    if (!silent) {
      isDiscoveringModels = true;
      notifyListeners();
    }
    final liveIds = await AiGatewayService.fetchLiveModels(aiConfig);
    availableModels = AiGatewayService.mergeCatalogWithLiveIds(liveIds);
    isDiscoveringModels = false;
    notifyListeners();
    return liveIds.length;
  }

  Future<ModelProbeStatus> probeModel(String modelId) async {
    final status = await AiGatewayService.probeModel(aiConfig, modelId);
    modelHealth[modelId] = status;
    notifyListeners();
    return status;
  }

  Future<void> probeTeamModels() async {
    final targets = <String>{
      aiConfig.primaryModel,
      ...aiConfig.teamModels,
      if (aiConfig.useSecondModelReview) aiConfig.reviewerModel,
    };
    await Future.wait(targets.map(probeModel));
  }

  Future<QuestionPack?> generateAiQuestionsPack({
    required Topic topic,
    required Difficulty difficulty,
    required QuestionFormat format,
    required int count,
    ExamKind? exam,
    String? lesson,
    String customPrompt = '',
    bool startImmediately = true,
  }) async {
    if (isGeneratingAiQuestions) return null;
    isGeneratingAiQuestions = true;
    aiGenerationStatus = 'Modeller hazırlanıyor...';
    notifyListeners();

    try {
      _ensurePoolKeysPopulated();
      final generated = await AiGatewayService.generateQuestionBatch(
        config: aiConfig,
        topic: topic,
        difficulty: difficulty,
        format: format,
        totalCount: count,
        exam: exam,
        lesson: lesson,
        customPrompt: customPrompt,
        existingPoolKeys: Set<String>.from(_poolKeys),
        onProgress: (done, model) {
          aiGenerationStatus = '$model çalışıyor ($done/$count soru hazır)...';
          notifyListeners();
        },
      );

      if (generated.isEmpty) {
        aiGenerationStatus = 'Sunucudan yeni soru alınamadı. CLIProxy bağlantısını kontrol et.';
        isGeneratingAiQuestions = false;
        notifyListeners();
        return null;
      }

      _mergeQuestions(generated);
      aiGeneratedRoundCount++;
      final today = _todayKey();
      if (dailyPoolDayKey != today) {
        dailyGeneratedByCategory.clear();
        dailyPoolDayKey = today;
      }
      for (final q in generated) {
        final key = q.category.label;
        dailyGeneratedByCategory[key] = (dailyGeneratedByCategory[key] ?? 0) + 1;
      }

      final usedModels = generated
          .map((q) => q.sourceModel ?? aiConfig.primaryModel)
          .toSet()
          .toList();
      final titleLabel = topic == Topic.custom && customPrompt.trim().isNotEmpty
          ? customPrompt.trim()
          : topic == Topic.exam && exam != null
              ? '${exam.label} · ${lesson ?? ""}'
              : topic.label;
      final pack = QuestionPack(
        id: 'pack_ai_${DateTime.now().millisecondsSinceEpoch}',
        title: 'AI · $titleLabel (${generated.length} Soru)',
        createdAt: DateTime.now(),
        models: usedModels,
        questions: generated,
      );
      offlinePacks.insert(0, pack);
      aiGenerationStatus = '${generated.length} özgün soru üretildi ve çevrimdışı kaydedildi!';
      isGeneratingAiQuestions = false;
      notifyListeners();
      unawaited(_savePersistedState());

      if (startImmediately) {
        startPackRound(pack);
      }
      return pack;
    } catch (e) {
      aiGenerationStatus =
          'Bağlantı hatası: ${e.toString().replaceFirst("Exception: ", "")}';
      isGeneratingAiQuestions = false;
      notifyListeners();
      return null;
    }
  }

  // --- JSON Pack Import/Export & Full .bilgilibackup ZIP ---
  Future<String> importJsonQuestionPacks() async {
    final files = await NativeBridge.pickFiles(mimeType: '*/*', allowMultiple: true);
    if (files.isEmpty) return 'Dosya seçilmedi.';
    _ensurePoolKeysPopulated();

    int addedQuestions = 0;
    int duplicateCount = 0;
    final addedIds = <String>[];
    String? latestPackId;

    for (final f in files) {
      try {
        final text = utf8.decode(f.bytes);
        final decoded = jsonDecode(text);
        QuestionPack pack;
        if (decoded is Map) {
          pack = QuestionPack.fromJson(Map<String, dynamic>.from(decoded));
        } else if (decoded is List) {
          final qs = <Question>[];
          for (var i = 0; i < decoded.length; i++) {
            if (decoded[i] is Map) {
              qs.add(Question.fromJson(Map<String, dynamic>.from(decoded[i] as Map), fallbackIndex: i));
            }
          }
          pack = QuestionPack(
            id: 'import_${DateTime.now().millisecondsSinceEpoch}',
            title: f.name.replaceAll('.json', ''),
            createdAt: DateTime.now(),
            models: const ['İçe Aktarılan JSON'],
            questions: qs,
          );
        } else {
          continue;
        }

        final fresh = <Question>[];
        for (final q in pack.questions) {
          if (_poolKeys.add(q.poolKey)) {
            _loadedIds.add(q.id);
            _allQuestions.add(q);
            _categoryCounts[q.category] = (_categoryCounts[q.category] ?? 0) + 1;
            if (q.visual != null) _visualCount++;
            if (q.activity != null) _activityCount++;
            fresh.add(q);
            addedIds.add(q.id);
            addedQuestions++;
          } else {
            duplicateCount++;
          }
        }
        if (pack.questions.isNotEmpty) {
          offlinePacks.insert(0, pack);
          latestPackId = pack.id;
        }
      } catch (_) {}
    }

    if (latestPackId != null) {
      lastImportedPackId = latestPackId;
      lastImportedQuestionIds = addedIds;
    }
    notifyListeners();
    unawaited(_savePersistedState());
    return '$addedQuestions yeni soru eklendi ($duplicateCount mükerrer atlandı).';
  }

  bool undoLastImport() {
    if (lastImportedPackId == null && lastImportedQuestionIds.isEmpty) return false;
    if (lastImportedPackId != null) {
      offlinePacks.removeWhere((p) => p.id == lastImportedPackId);
    }
    final removeSet = lastImportedQuestionIds.toSet();
    final removedKeys = _allQuestions
        .where((q) => removeSet.contains(q.id))
        .map((q) => q.poolKey)
        .toSet();
    _allQuestions.removeWhere((q) => removeSet.contains(q.id));
    _loadedIds.removeAll(removeSet);
    _poolKeys.removeAll(removedKeys);
    _recomputePoolStats();
    lastImportedPackId = null;
    lastImportedQuestionIds = [];
    notifyListeners();
    unawaited(_savePersistedState());
    return true;
  }

  Future<bool> exportQuestionPack(QuestionPack pack) async {
    final bytes = Uint8List.fromList(utf8.encode(pack.toPrettyJson()));
    final safeTitle = pack.title.replaceAll(RegExp(r'[^\w\-]+'), '_');
    return NativeBridge.saveFile(
      fileName: 'Bilgili_$safeTitle.json',
      mimeType: 'application/json',
      bytes: bytes,
    );
  }

  Future<bool> exportFullBackup() async {
    final stateMap = _buildStateMap();
    final archive = Archive();
    final stateBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(stateMap));
    archive.addFile(ArchiveFile('bilgili_state_v3.json', stateBytes.length, stateBytes));
    final zipped = ZipEncoder().encode(archive);
    if (zipped == null) return false;
    return NativeBridge.saveFile(
      fileName: 'Bilgili_Yedek_${_todayKey()}.bilgilibackup',
      mimeType: 'application/octet-stream',
      bytes: Uint8List.fromList(zipped),
    );
  }

  Future<String> restoreFullBackup() async {
    final picked = await NativeBridge.pickFiles(mimeType: '*/*', allowMultiple: false);
    if (picked.isEmpty) return 'Yedek dosyası seçilmedi.';
    try {
      final file = picked.first;
      Map<String, dynamic>? restored;
      if (file.name.endsWith('.json')) {
        restored = Map<String, dynamic>.from(jsonDecode(utf8.decode(file.bytes)) as Map);
      } else {
        final archive = ZipDecoder().decodeBytes(file.bytes);
        for (final entry in archive) {
          if (entry.isFile && entry.name.endsWith('.json')) {
            final content = utf8.decode(entry.content as List<int>);
            restored = Map<String, dynamic>.from(jsonDecode(content) as Map);
            break;
          }
        }
      }
      if (restored == null) return 'Geçerli bir Bilgili yedeği bulunamadı.';
      _applyStateMap(restored);
      notifyListeners();
      await _savePersistedState();
      return 'Tam yedek başarıyla geri yüklendi!';
    } catch (e) {
      return 'Yedek okunamadı: $e';
    }
  }

  Future<void> resetAllProgress() async {
    xp = 0;
    dailyStreak = 1;
    completedDailyChallengeDayKey = null;
    playedQuestionIds.clear();
    reportedQuestionIds.clear();
    categoryAnswered.clear();
    categoryCorrect.clear();
    savedBookmarks.clear();
    reviewDeck.clear();
    history.clear();
    notifyListeners();
    await _savePersistedState();
  }

  // --- Badges ---
  List<ArenaBadgeInfo> get badges {
    final hasFlawless = history.any((h) => h.totalQuestions >= 5 && h.correctCount == h.totalQuestions);
    final hasVoiceRound = history.any((h) => h.wasLiveVoice);
    final hasDuelRound = history.any((h) => h.duelStandings.isNotEmpty);
    return [
      ArenaBadgeInfo(
        id: 'first_step',
        title: 'İlk Adım',
        description: 'İlk bilgi turunu tamamla',
        iconKind: IconDataCompat.spark,
        unlocked: history.isNotEmpty,
      ),
      ArenaBadgeInfo(
        id: 'curious',
        title: 'Meraklı Kaşif',
        description: 'En az 50 soruyu yanıtla',
        iconKind: IconDataCompat.curious,
        unlocked: playedQuestionIds.length >= 50,
      ),
      ArenaBadgeInfo(
        id: 'flawless',
        title: 'Kusursuz Tur',
        description: 'Bir turu %100 doğrulukla bitir',
        iconKind: IconDataCompat.flawless,
        unlocked: hasFlawless,
      ),
      ArenaBadgeInfo(
        id: 'master',
        title: 'Bilgi Ustası',
        description: 'Seviye 5 ve üzerine ulaş',
        iconKind: IconDataCompat.master,
        unlocked: level >= 5,
      ),
      ArenaBadgeInfo(
        id: 'collector',
        title: 'Koleksiyoncu',
        description: 'Bilgi Defterine 5 soru kaydet',
        iconKind: IconDataCompat.collector,
        unlocked: savedBookmarks.length >= 5,
      ),
      ArenaBadgeInfo(
        id: 'ai_explorer',
        title: 'Model Kaşifi',
        description: 'CLIProxy / AI ile özgün soru paketi üret',
        iconKind: IconDataCompat.aiExplorer,
        unlocked: aiGeneratedRoundCount >= 1 ||
            offlinePacks.any((p) => !p.id.startsWith('builtin_sb_')),
      ),
      ArenaBadgeInfo(
        id: 'voice_star',
        title: 'Sesli Şampiyon',
        description: 'Canlı Sesli Yarışma turu tamamla',
        iconKind: IconDataCompat.voiceStar,
        unlocked: hasVoiceRound,
      ),
      ArenaBadgeInfo(
        id: 'duel_king',
        title: 'Düello Ustası',
        description: 'Çok oyunculu bir düello turnuvası bitir',
        iconKind: IconDataCompat.duelKing,
        unlocked: hasDuelRound,
      ),
    ];
  }

  // --- Persistence ---
  Map<String, dynamic> _buildStateMap() => {
        'version': 3,
        'xp': xp,
        'dailyStreak': dailyStreak,
        'lastPlayedDayKey': lastPlayedDayKey,
        'completedDailyChallengeDayKey': completedDailyChallengeDayKey,
        'playedQuestionIds': playedQuestionIds.take(4000).toList(),
        'reportedQuestionIds': reportedQuestionIds.toList(),
        'categoryAnswered': categoryAnswered,
        'categoryCorrect': categoryCorrect,
        'savedBookmarks': savedBookmarks.map((q) => q.toJson()).toList(),
        'reviewDeck': reviewDeck.map((c) => c.toJson()).toList(),
        'offlinePacks': offlinePacks
            .where((p) => !p.id.startsWith('builtin_sb_'))
            .map((p) => p.toJson())
            .toList(),
        'history': history.map((h) => h.toJson()).toList(),
        'studyProfiles': studyProfiles.map((p) => p.toJson()).toList(),
        'aiConfig': aiConfig.toJson(),
        'aiGeneratedRoundCount': aiGeneratedRoundCount,
        'dailyPoolDayKey': dailyPoolDayKey,
        'dailyGeneratedByCategory': dailyGeneratedByCategory,
        'wallpaperId': wallpaperId,
        'wallpaperClarity': wallpaperClarity.name,
        'effectIntensity': effectIntensity.name,
        'menuMusicEnabled': menuMusicEnabled,
        'gameMusicEnabled': gameMusicEnabled,
        'musicVolume': musicVolume,
        'sfxEnabled': sfxEnabled,
        'hapticsEnabled': hapticsEnabled,
        'ttsVoice': ttsVoice,
        'ttsSpeechRate': ttsSpeechRate,
        'voiceReviewSeconds': voiceReviewSeconds,
        'liveVoiceExplain': liveVoiceExplain,
        'highContrast': highContrast,
        'readingScale': readingScale,
        'reduceMotion': reduceMotion,
      };

  void _applyStateMap(Map<String, dynamic> map) {
    xp = (map['xp'] as num?)?.toInt() ?? 0;
    dailyStreak = (map['dailyStreak'] as num?)?.toInt() ?? 1;
    lastPlayedDayKey = map['lastPlayedDayKey']?.toString();
    completedDailyChallengeDayKey = map['completedDailyChallengeDayKey']?.toString();

    playedQuestionIds
      ..clear()
      ..addAll((map['playedQuestionIds'] as List?)?.map((e) => e.toString()) ?? const []);
    reportedQuestionIds
      ..clear()
      ..addAll((map['reportedQuestionIds'] as List?)?.map((e) => e.toString()) ?? const []);

    categoryAnswered.clear();
    if (map['categoryAnswered'] is Map) {
      for (final e in (map['categoryAnswered'] as Map).entries) {
        categoryAnswered[e.key.toString()] = (e.value as num?)?.toInt() ?? 0;
      }
    }
    categoryCorrect.clear();
    if (map['categoryCorrect'] is Map) {
      for (final e in (map['categoryCorrect'] as Map).entries) {
        categoryCorrect[e.key.toString()] = (e.value as num?)?.toInt() ?? 0;
      }
    }

    savedBookmarks
      ..clear()
      ..addAll(
        ((map['savedBookmarks'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Question.fromJson(Map<String, dynamic>.from(m))),
      );

    reviewDeck
      ..clear()
      ..addAll(
        ((map['reviewDeck'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => ReviewCard.fromJson(Map<String, dynamic>.from(m))),
      );

    offlinePacks
      ..removeWhere((p) => !p.id.startsWith('builtin_sb_'))
      ..insertAll(
        0,
        ((map['offlinePacks'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => QuestionPack.fromJson(Map<String, dynamic>.from(m))),
      );
    for (final p in offlinePacks) {
      if (!p.id.startsWith('builtin_sb_')) {
        _mergeQuestions(p.questions);
      }
    }

    history
      ..clear()
      ..addAll(
        ((map['history'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => RoundSummary.fromJson(Map<String, dynamic>.from(m))),
      );

    if (map['studyProfiles'] is List) {
      final parsedProfiles = (map['studyProfiles'] as List)
          .whereType<Map>()
          .map((m) => StudyProfile.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (parsedProfiles.isNotEmpty) studyProfiles = parsedProfiles;
    }

    if (map['aiConfig'] is Map) {
      aiConfig = AiGatewayConfig.fromJson(Map<String, dynamic>.from(map['aiConfig'] as Map));
    }
    aiGeneratedRoundCount = (map['aiGeneratedRoundCount'] as num?)?.toInt() ?? 0;
    dailyPoolDayKey = map['dailyPoolDayKey']?.toString() ?? _todayKey();
    dailyGeneratedByCategory.clear();
    if (dailyPoolDayKey == _todayKey() && map['dailyGeneratedByCategory'] is Map) {
      for (final e in (map['dailyGeneratedByCategory'] as Map).entries) {
        dailyGeneratedByCategory[e.key.toString()] = (e.value as num?)?.toInt() ?? 0;
      }
    }

    wallpaperId = map['wallpaperId']?.toString() ?? 'observatory';
    wallpaperClarity = WallpaperClarity.values.firstWhere(
      (c) => c.name == map['wallpaperClarity'],
      orElse: () => WallpaperClarity.balanced,
    );
    effectIntensity = EffectIntensity.values.firstWhere(
      (e) => e.name == map['effectIntensity'],
      orElse: () => EffectIntensity.rich,
    );
    menuMusicEnabled = map['menuMusicEnabled'] == true;
    gameMusicEnabled = map['gameMusicEnabled'] != false;
    musicVolume = (map['musicVolume'] as num?)?.toDouble() ?? 0.32;
    sfxEnabled = map['sfxEnabled'] != false;
    hapticsEnabled = map['hapticsEnabled'] != false;
    final savedVoice = map['ttsVoice']?.toString().trim() ?? '';
    ttsVoice = savedVoice.isEmpty ? NativeBridge.defaultTtsVoice : savedVoice;
    unawaited(NativeBridge.setTtsVoice(ttsVoice));
    ttsSpeechRate = (map['ttsSpeechRate'] as num?)?.toDouble() ?? 1.02;
    voiceReviewSeconds = (map['voiceReviewSeconds'] as num?)?.toInt() ?? 2;
    liveVoiceExplain = map['liveVoiceExplain'] != false;
    highContrast = map['highContrast'] == true;
    readingScale = (map['readingScale'] as num?)?.toDouble() ?? 1.0;
    reduceMotion = map['reduceMotion'] == true;
  }

  Future<File> _stateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/bilgili_state_v3.json');
  }

  Future<void> _loadPersistedState() async {
    try {
      final f = await _stateFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _applyStateMap(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {}
  }

  Future<void> _savePersistedState() async {
    if (!persistToDisk) return;
    try {
      final f = await _stateFile();
      await f.writeAsString(jsonEncode(_buildStateMap()));
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopRoundTimer();
    _voiceSub?.cancel();
    super.dispose();
  }
}
