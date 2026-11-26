import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../data/advanced/catalog.dart';
import '../data/advanced/common.dart' show StudyLevel;
import '../models/quiz_models.dart';
import '../services/ai_gateway_service.dart';
import '../services/native_bridge.dart';
import '../services/voice_answer_resolver.dart';
import '../theme/arena_design.dart';
import 'arena_rooms.dart';

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
  String creationResponse = '';
  bool get needsCreation => current.creation != null && creationResponse.trim().isEmpty;
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
  final List<int> rivalScores;
  final List<int> rivalCorrects;
  final List<int> rivalStreaks;
  final Random rivalRng;

  ActiveRound({
    required this.id,
    required this.title,
    required this.setup,
    required this.questions,
  })  : duelScores = List<int>.filled(setup.duelPlayerNames.length, 0),
        duelCorrects = List<int>.filled(setup.duelPlayerNames.length, 0),
        rivalScores = List<int>.filled(setup.rivalNames.length, 0),
        rivalCorrects = List<int>.filled(setup.rivalNames.length, 0),
        rivalStreaks = List<int>.filled(setup.rivalNames.length, 0),
        rivalRng = Random(id.hashCode);

  bool get hasRivals => setup.rivalNames.isNotEmpty;

  /// Rakip i'nin bilme olasılığı: 0,55 ile 0,80 arasında, adına göre sabit.
  double rivalSkill(int i) => 0.55 + (setup.rivalNames[i].hashCode % 26).abs() / 100;

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
  final int current;
  final int target;
  final String group;

  const ArenaBadgeInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.iconKind,
    required this.unlocked,
    this.current = 0,
    this.target = 1,
    this.group = 'Genel',
  });

  double get progress =>
      unlocked ? 1.0 : (target <= 0 ? 0.0 : (current / target).clamp(0.0, 1.0));
}

enum IconDataCompat {
  spark,
  curious,
  hunter,
  encyclopedia,
  flawless,
  streak,
  master,
  sage,
  explorer5,
  explorer23,
  zirveMid,
  zirveTop,
  collector,
  dailyHabit,
  voiceStar,
  duelKing,
}

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
  /// Etkinlik anahtarı → kullanılan deneme sayısı ve en yüksek puan.
  final Map<String, int> etkinlikDenemeleri = {};
  final Map<String, int> etkinlikEnIyi = {};
  String? _aktifEtkinlik;
  /// Zirve Merdiveni: en yüksek kazanç ve ulaşılan en üst basamak.
  int zirveEnIyi = 0;
  int zirveEnUstBasamak = 0;
  int dailyStreak = 1;
  String? lastPlayedDayKey;
  String? completedDailyChallengeDayKey;
  final Set<String> playedQuestionIds = {};
  final Set<String> reportedQuestionIds = {};
  final Map<String, int> categoryAnswered = {};
  final Map<String, int> categoryCorrect = {};
  final List<Question> savedBookmarks = [];
  final Map<String, String> creationPortfolio = {};
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
  static const int _currentUiThemeRev = 318;
  String wallpaperId = 'istanbul_bogaz';
  WallpaperClarity wallpaperClarity = WallpaperClarity.vivid;
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
    _addAcademicPacks();
    _voiceSub = NativeBridge.voiceEvents.listen(_onNativeVoiceEvent);
  }

  factory ArenaController.inMemoryForTest({List<Question>? seedQuestions}) {
    NativeBridge.testMode = true;
    final ctrl = ArenaController(persistToDisk: false);
    if (seedQuestions != null) ctrl._mergeQuestions(seedQuestions);
    ctrl.isFullPoolLoaded = true;
    return ctrl;
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  int get level => (xp ~/ 250) + 1;
  int get xpInCurrentLevel => xp % 250;
  List<Question> get personalQuestions => UnmodifiableListView(_allQuestions);
  List<Question> get allQuestions => JoinedQuestions(_allQuestions, AdvancedCatalog.all);
  int get totalPoolCount => _allQuestions.length + AdvancedCatalog.all.length;
  int get visualQuestionCount => _visualCount + AdvancedCatalog.visuals.length;
  int get activityQuestionCount => _activityCount + AdvancedCatalog.activityCount;
  ArenaWallpaper get currentWallpaper => ArenaWallpapers.byId(wallpaperId);

  Question? questionById(String id) =>
      AdvancedCatalog.questionById(id) ?? _allQuestions.where((q) => q.id == id).firstOrNull ??
      savedBookmarks.where((q) => q.id == id).firstOrNull ??
      reviewDeck.where((card) => card.question.id == id).firstOrNull?.question;

  List<Topic> get availableTopics => Topic.poolCategories.where((t) => countForTopic(t) > 0).toList();

  int countForTopic(Topic t) {
    if (t == Topic.mixed || t == Topic.custom) return totalPoolCount;
    return (_categoryCounts[t] ?? 0) + AdvancedCatalog.topicCounts[t]!;
  }

  int countForTopics(Set<Topic> topics) {
    final active = topics.where((t) => t != Topic.mixed && t != Topic.custom).toSet();
    if (active.isEmpty) return totalPoolCount;
    var sum = 0;
    for (final t in active) {
      sum += countForTopic(t);
    }
    return min(sum, totalPoolCount);
  }

  /// Akademi havuzundaki etkin filtre kombinasyonuna uyan yaklaşık soru sayısını O(1) döndürür.
  int countFilteredPool({
    Set<Topic>? topics,
    Difficulty? difficulty,
    BloomLevel? bloom,
    QuestionFormat format = QuestionFormat.mixed,
    PoolCollection collection = PoolCollection.all,
  }) {
    final activeTopics = topics
            ?.where((t) => t != Topic.mixed && t != Topic.custom)
            .toSet() ??
        const <Topic>{};
    var total = 0;
    if (collection != PoolCollection.personal) {
      total += AdvancedCatalog.select(
        topic: activeTopics.length == 1 ? activeTopics.first : Topic.mixed,
        topics: activeTopics.length > 1 ? activeTopics : null,
        format: format,
        level: collection.level,
        bloom: bloom,
        difficulty: difficulty,
      ).length;
    }
    if (collection.level == null && bloom == null) {
      for (final q in _allQuestions) {
        if (activeTopics.isNotEmpty) {
          final hit = activeTopics.contains(q.category) ||
              (activeTopics.contains(Topic.exam) && q.exam != null);
          if (!hit) continue;
        }
        if (difficulty != null && q.difficulty != difficulty) continue;
        if (!q.matchesFormat(format)) continue;
        total++;
      }
    }
    return total;
  }

  List<ReviewCard> get dueReviewCards {
    final now = DateTime.now();
    return reviewDeck.where((c) => !c.due.isAfter(now)).toList();
  }

  bool get isDailyChallengeDoneToday => completedDailyChallengeDayKey == _todayKey();

  Future<void> initialize() async {
    if (isLoadingPool || isFullPoolLoaded) return;
    isLoadingPool = true;
    notifyListeners();
    if (persistToDisk) await _loadPersistedState();

    isFullPoolLoaded = true;
    isLoadingPool = false;
    _syncBackgroundMusic();
    notifyListeners();
  }

  void _mergeQuestions(Iterable<Question> incoming) {
    for (final q in incoming) {
      if (q.text.trim().isEmpty) continue;
      if (AdvancedCatalog.hasId(q.id) || !_loadedIds.add(q.id)) continue;
      final key = q.poolKey;
      if (_poolKeys.add(key)) {
        _allQuestions.add(q);
        _countPersonalQuestion(q);
      }
    }
  }

  void _countPersonalQuestion(Question q) {
    _categoryCounts[q.category] = (_categoryCounts[q.category] ?? 0) + 1;
    if (q.exam != null && q.category != Topic.exam) {
      _categoryCounts[Topic.exam] = (_categoryCounts[Topic.exam] ?? 0) + 1;
    }
    if (q.visual != null) _visualCount++;
    if (q.activity != null) _activityCount++;
  }

  void _recomputePoolStats() {
    _categoryCounts.clear();
    _visualCount = 0;
    _activityCount = 0;
    for (final q in _allQuestions) {
      _countPersonalQuestion(q);
    }
  }

  void _addAcademicPacks() {
    void add(String id, String title, FamilyQuestions questions) {
      if (questions.isEmpty) return;
      offlinePacks.add(QuestionPack(
        id: 'builtin_sb_ak38_$id',
        title: title,
        createdAt: DateTime(2026, 11, 21),
        models: const ['GPT-6.2 Astra'],
        questions: questions,
      ));
    }
    for (final level in StudyLevel.values) {
      add(level.name, '${level.label} · Akademik Soru Bankası',
          AdvancedCatalog.select(level: level));
    }
    add('ozgun', 'Özgün Soru Bankası', AdvancedCatalog.ozgun);
    add('studio_100k', '100.000 Metin Dışı Stüdyo · Tümü', AdvancedCatalog.studio100k);
    add('studio_visual_50k', 'Yeni Nesil Görsel Stüdyo · 50.000', AdvancedCatalog.studioVisual50k);
    add('studio_audio_en_25k', 'Sesli İngilizce Stüdyosu · 25.000', AdvancedCatalog.studioAudioEnglish25k);
    add('studio_interactive_25k', '3D Etkileşimli Stüdyo · 25.000', AdvancedCatalog.studioInteractive25k);
    add('studio_10k', 'Yeni Nesil 10.000 Seçki · Tümü', AdvancedCatalog.studio10k);
    add('studio_visual_4k', 'Yeni Nesil Görsel Stüdyo · 4.000', AdvancedCatalog.studioVisual4k);
    add('studio_audio_en_3k', 'Sesli İngilizce Stüdyosu · 3.000', AdvancedCatalog.studioAudioEnglish3k);
    add('studio_interactive_3k', 'Çok Biçimli Etkileşimli · 3.000', AdvancedCatalog.studioInteractive3k);
    add('lise_metin', 'Lise · Metin Soru Bankası',
        AdvancedCatalog.select(level: StudyLevel.lise, format: QuestionFormat.text));
    for (final bloom in BloomLevel.values) {
      add('bloom_${bloom.name}', 'Bloom · ${bloom.label}', AdvancedCatalog.select(bloom: bloom));
    }
    for (final topic in Topic.poolCategories) {
      add('topic_${topic.name}', '${topic.label} · Konu Bankası', AdvancedCatalog.select(topic: topic));
    }
    for (final format in QuestionFormat.values.where((f) => f != QuestionFormat.mixed && f != QuestionFormat.text)) {
      add('format_${format.name}', '${format.label} · Soru Türü', AdvancedCatalog.select(format: format));
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

  /// Özel ekranların (Zirve Merdiveni) çaldığı müzik parçası; null ise
  /// menü/oyun müziği kuralı geçerlidir.
  String? ozelMuzik;

  void ozelMuzikAyarla(String? parca) {
    ozelMuzik = parca;
    _syncBackgroundMusic();
  }

  void _syncBackgroundMusic() {
    if (ozelMuzik != null) {
      NativeBridge.setMusic(gameMusicEnabled ? ozelMuzik : null, volume: musicVolume);
      return;
    }
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

  /// Birden fazla kategori seçmek veya seçimi kaldırmak için kullanılır.
  void toggleTopicSelection(Topic t) {
    if (t == Topic.mixed) {
      setup = setup.copyWith(topic: Topic.mixed, selectedTopics: const {});
      notifyListeners();
      return;
    }
    if (t == Topic.custom) {
      setup = setup.copyWith(topic: Topic.custom, selectedTopics: const {});
      notifyListeners();
      return;
    }
    final next = Set<Topic>.of(setup.effectiveTopics);
    if (!next.remove(t)) {
      next.add(t);
    }
    if (next.isEmpty) {
      setup = setup.copyWith(topic: Topic.mixed, selectedTopics: const {});
    } else if (next.length == 1) {
      setup = setup.copyWith(topic: next.first, selectedTopics: next);
    } else {
      setup = setup.copyWith(topic: Topic.mixed, selectedTopics: next);
    }
    notifyListeners();
  }

  void selectTopicBundle(Set<Topic> topics) {
    final clean = topics.where((t) => t != Topic.mixed && t != Topic.custom).toSet();
    if (clean.isEmpty) {
      setup = setup.copyWith(topic: Topic.mixed, selectedTopics: const {});
    } else if (clean.length == 1) {
      setup = setup.copyWith(topic: clean.first, selectedTopics: clean);
    } else {
      setup = setup.copyWith(topic: Topic.mixed, selectedTopics: clean);
    }
    notifyListeners();
  }

  void clearSelectedTopics() {
    setup = setup.copyWith(topic: Topic.mixed, selectedTopics: const {});
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
    final manual = cfg.format == QuestionFormat.fill ||
        cfg.format == QuestionFormat.dictation ||
        cfg.format == QuestionFormat.multiSelect ||
        cfg.format == QuestionFormat.slider ||
        cfg.format == QuestionFormat.anagram;
    final quick = cfg.mode == GameMode.sprint || (cfg.liveVoiceHost && !manual);
    final format = quick &&
            {
              QuestionFormat.mixed,
              QuestionFormat.fill,
              QuestionFormat.dictation,
              QuestionFormat.creation,
              QuestionFormat.multiSelect,
              QuestionFormat.slider,
              QuestionFormat.anagram,
              QuestionFormat.visual,
              QuestionFormat.text,
            }.contains(cfg.format)
        ? QuestionFormat.multipleChoice
        : cfg.format;
    final bool? requireVisual = quick && cfg.format == QuestionFormat.visual ? true
        : quick && cfg.format == QuestionFormat.text ? false : null;
    bool matches(Question q) => !reportedQuestionIds.contains(q.id) &&
        q.matchesFormat(format) && (requireVisual == null || (q.visual != null) == requireVisual);

    final activeTopics = cfg.effectiveTopics;
    final singleExam = activeTopics.length == 1 && activeTopics.first == Topic.exam;

    final candidates = _allQuestions.where((q) {
      if (!matches(q)) return false;
      if (activeTopics.isNotEmpty) {
        if (singleExam) {
          if (q.category != Topic.exam && q.exam == null) return false;
          if (q.exam != null && q.exam != cfg.exam) return false;
          if (cfg.lesson != null &&
              cfg.lesson!.isNotEmpty &&
              q.lesson != null &&
              q.lesson != cfg.lesson) {
            return false;
          }
        } else {
          final hit = activeTopics.contains(q.category) ||
              (activeTopics.contains(Topic.exam) && q.exam != null);
          if (!hit) return false;
        }
      }
      if (cfg.difficulty != null && q.difficulty != cfg.difficulty) {
        return false;
      }
      return true;
    }).toList();

    final academic = AdvancedCatalog.select(
      topic: singleExam ? Topic.exam : cfg.topic,
      topics: activeTopics.length > 1 ? activeTopics : null,
      difficulty: cfg.difficulty, format: format, requireVisual: requireVisual,
      exam: singleExam ? cfg.exam : null,
      lesson: singleExam ? cfg.lesson : null,
    );
    final pool = JoinedQuestions(candidates, academic);

    // Prioritize unplayed questions with fast random sampling on large pools
    return _pickRandomQuestions(pool, cfg.questionCount, rng);
  }

  List<Question> _pickRandomQuestions(List<Question> pool, int targetCount, Random rng) {
    if (pool.isEmpty) return const [];
    if (pool.length <= 600) {
      final unplayed = pool.where((q) => !reportedQuestionIds.contains(q.id) && !playedQuestionIds.contains(q.id)).toList()..shuffle(rng);
      final played = pool.where((q) => !reportedQuestionIds.contains(q.id) && playedQuestionIds.contains(q.id)).toList()..shuffle(rng);
      final combined = [...unplayed, ...played];
      return combined.take(targetCount).map((q) => q.shuffled(rng)).toList();
    }

    final picked = <Question>[];
    final pickedIds = <String>{};
    final maxAttempts = targetCount * 8;
    // Pass 1: random unplayed picks
    for (var i = 0; i < maxAttempts && picked.length < targetCount; i++) {
      final q = pool[rng.nextInt(pool.length)];
      if (!reportedQuestionIds.contains(q.id) && !playedQuestionIds.contains(q.id) && pickedIds.add(q.id)) {
        picked.add(q.shuffled(rng));
      }
    }
    // Pass 2: random fallback from pool if needed
    for (var i = 0; i < maxAttempts && picked.length < targetCount; i++) {
      final q = pool[rng.nextInt(pool.length)];
      if (!reportedQuestionIds.contains(q.id) && pickedIds.add(q.id)) {
        picked.add(q.shuffled(rng));
      }
    }
    if (picked.length < targetCount) {
      for (var i = 0; i < pool.length && picked.length < targetCount; i++) {
        final q = pool[i];
        if (!reportedQuestionIds.contains(q.id) && pickedIds.add(q.id)) {
          picked.add(q.shuffled(rng));
        }
      }
    }
    return picked;
  }

  bool startConfiguredRound({String? customTitle, RoundSetup? overrideSetup, int? seed}) {
    final cfg = overrideSetup ?? setup;
    final qs = sampleQuestions(cfg, seed: seed);
    if (qs.isEmpty) return false;
    _beginRound(
      title: customTitle ??
          (cfg.duelPlayerNames.length >= 2
              ? 'Düello Arenası (${cfg.duelPlayerNames.length} Oyuncu)'
              : cfg.liveVoiceHost
                  ? 'Canlı Sesli Yarışma'
                  : '${cfg.topicsLabel} · ${cfg.mode.label}'),
      cfg: cfg,
      questions: qs,
    );
    return true;
  }

  bool startLiveVoiceQuiz() {
    final liveCfg = setup.copyWith(
      liveVoiceHost: true,
      mode: GameMode.classic,
      questionCount: 8,
    );
    return startConfiguredRound(
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
    void addFrom(List<Question> questions, int count, {int cap = 14}) {
      for (final q in _pickRandomQuestions(questions, count, _rng)) {
        if (picked.length < cap && pickedIds.add(q.id)) picked.add(q);
      }
    }
    for (final kind in [
      VisualKind.circuit,
      VisualKind.venn,
      VisualKind.compass,
      VisualKind.colorLab,
      VisualKind.piano,
      VisualKind.flag,
      VisualKind.clock,
      VisualKind.atom,
      VisualKind.matrix,
    ]) {
      addFrom(AdvancedCatalog.select(visualKind: kind), 1);
    }
    for (final format in [
      QuestionFormat.slider,
      QuestionFormat.anagram,
      QuestionFormat.listening,
      QuestionFormat.dictation,
      QuestionFormat.matching,
    ]) {
      addFrom(AdvancedCatalog.select(format: format), 1);
    }
    if (picked.length < 14) {
      addFrom(_allQuestions.where((q) => q.visual != null || q.activity != null).toList(), 14);
    }
    if (picked.length < 14) addFrom(AdvancedCatalog.visuals, 14);
    if (picked.isEmpty) return;
    picked.shuffle(_rng);
    _beginRound(
      title: 'Görsel & Etkileşimli Keşif (14 Tür)',
      cfg: RoundSetup(mode: GameMode.training, questionCount: picked.length),
      questions: picked,
    );
  }

  bool startVisualEngineRound({
    List<VisualKind>? kinds,
    QuestionFormat? format,
    String? title,
    int count = 10,
  }) {
    final List<Question> picked;
    if (kinds != null && kinds.isNotEmpty) {
      final bag = <Question>[];
      final seen = <String>{};
      final perKind = max(1, (count / kinds.length).ceil());
      for (final k in kinds) {
        for (final q in _pickRandomQuestions(AdvancedCatalog.select(visualKind: k), perKind, _rng)) {
          if (seen.add(q.id)) bag.add(q);
        }
      }
      bag.shuffle(_rng);
      picked = bag.take(count).toList();
    } else if (format != null) {
      picked = _pickRandomQuestions(AdvancedCatalog.select(format: format), count, _rng);
    } else {
      picked = _pickRandomQuestions(AdvancedCatalog.studioVisual50k, count, _rng);
    }
    if (picked.isEmpty) return false;
    _beginRound(
      title: title ?? 'Görsel & Etkileşimli Stüdyo',
      cfg: RoundSetup(
        format: format ?? QuestionFormat.visual,
        mode: GameMode.training,
        questionCount: picked.length,
      ),
      questions: picked,
    );
    return true;
  }

  bool startAudioEnglishStudio({QuestionFormat? format, int count = 10}) {
    final List<Question> source;
    final String title;
    switch (format) {
      case QuestionFormat.listening:
        source = AdvancedCatalog.select(topic: Topic.language, format: QuestionFormat.listening);
        title = 'Sesli İngilizce · Dinleme & Anlama';
        break;
      case QuestionFormat.dictation:
        source = AdvancedCatalog.select(topic: Topic.language, format: QuestionFormat.dictation);
        title = 'Sesli İngilizce · Dikte Stüdyosu';
        break;
      case QuestionFormat.pronunciation:
        source = AdvancedCatalog.select(topic: Topic.language, format: QuestionFormat.pronunciation);
        title = 'Sesli İngilizce · Telaffuz & Konuşma';
        break;
      case QuestionFormat.anagram:
        source = AdvancedCatalog.select(topic: Topic.language, format: QuestionFormat.anagram);
        title = 'Sesli İngilizce · 3D Harf Dizme';
        break;
      case QuestionFormat.visual:
        source = AdvancedCatalog.select(topic: Topic.language, format: QuestionFormat.visual);
        title = 'İngilizce Görsel Saat Stüdyosu';
        break;
      case QuestionFormat.ordering:
        source = AdvancedCatalog.select(topic: Topic.language, format: QuestionFormat.ordering);
        title = 'İngilizce Cümle Kurma (Word Order)';
        break;
      case QuestionFormat.matching:
        source = AdvancedCatalog.select(topic: Topic.language, format: QuestionFormat.matching);
        title = 'İngilizce Deyim & Fiil Eşleştirme';
        break;
      default:
        source = AdvancedCatalog.studioAudioEnglishAll;
        title = 'Sesli İngilizce Stüdyosu (28.000)';
    }
    final qs = _pickRandomQuestions(source, count, _rng);
    if (qs.isEmpty) return false;
    _beginRound(
      title: title,
      cfg: RoundSetup(
        topic: Topic.language,
        format: format ?? QuestionFormat.mixed,
        mode: GameMode.training,
        questionCount: qs.length,
      ),
      questions: qs,
    );
    return true;
  }

  bool startSpacedRepetitionReview() => startReviewRound();

  bool startReviewRound({int? boxFilter, Topic? topicFilter, bool onlyDue = false}) {
    Iterable<ReviewCard> source = onlyDue
        ? dueReviewCards
        : (dueReviewCards.isNotEmpty && boxFilter == null && topicFilter == null
            ? dueReviewCards
            : reviewDeck);
    if (boxFilter != null) {
      source = reviewDeck.where((c) => c.box == boxFilter);
    }
    if (topicFilter != null && topicFilter != Topic.mixed) {
      source = source.where((c) => c.question.category == topicFilter);
    }
    final list = source.toList();
    if (list.isEmpty) return false;
    final qs = list.take(15).map((c) => c.question.shuffled(_rng)).toList();
    final label = boxFilter != null
        ? 'Tekrar · Kutu ${boxFilter + 1}'
        : topicFilter != null && topicFilter != Topic.mixed
            ? 'Tekrar · ${topicFilter.label}'
            : 'Aralıklı Tekrar Turu';
    _beginRound(
      title: label,
      cfg: RoundSetup(
        topic: topicFilter ?? Topic.mixed,
        mode: GameMode.training,
        questionCount: qs.length,
      ),
      questions: qs,
    );
    return true;
  }

  bool startBookmarksRound({Topic? topicFilter, int maxQuestions = 15}) {
    final list = (topicFilter == null || topicFilter == Topic.mixed)
        ? List<Question>.of(savedBookmarks)
        : savedBookmarks.where((q) => q.category == topicFilter).toList();
    if (list.isEmpty) return false;
    list.shuffle(_rng);
    final qs = list.take(maxQuestions).map((q) => q.shuffled(_rng)).toList();
    _beginRound(
      title: topicFilter != null && topicFilter != Topic.mixed
          ? 'Defterim · ${topicFilter.label}'
          : 'Bilgi Defterim Turu',
      cfg: RoundSetup(
        topic: topicFilter ?? Topic.mixed,
        mode: GameMode.training,
        questionCount: qs.length,
      ),
      questions: qs,
    );
    return true;
  }

  bool startFilteredAcademyRound({
    Set<Topic>? topics,
    Difficulty? difficulty,
    BloomLevel? bloom,
    QuestionFormat format = QuestionFormat.mixed,
    PoolCollection collection = PoolCollection.all,
    int count = 10,
    GameMode mode = GameMode.classic,
  }) {
    final activeTopics = topics
            ?.where((t) => t != Topic.mixed && t != Topic.custom)
            .toSet() ??
        const <Topic>{};
    final personalCandidates = <Question>[];
    if (collection.level == null && bloom == null) {
      for (final q in _allQuestions) {
        if (reportedQuestionIds.contains(q.id)) continue;
        if (activeTopics.isNotEmpty) {
          final hit = activeTopics.contains(q.category) ||
              (activeTopics.contains(Topic.exam) && q.exam != null);
          if (!hit) continue;
        }
        if (difficulty != null && q.difficulty != difficulty) continue;
        if (!q.matchesFormat(format)) continue;
        personalCandidates.add(q);
      }
    }
    final academic = collection == PoolCollection.personal
        ? FamilyQuestions(const [])
        : AdvancedCatalog.select(
            topic: activeTopics.length == 1 ? activeTopics.first : Topic.mixed,
            topics: activeTopics.length > 1 ? activeTopics : null,
            format: format,
            level: collection.level,
            bloom: bloom,
            difficulty: difficulty,
          );
    final pool = JoinedQuestions(personalCandidates, academic);
    final picked = _pickRandomQuestions(pool, count, _rng);
    if (picked.isEmpty) return false;
    final parts = <String>[
      if (activeTopics.length == 1)
        activeTopics.first.label
      else if (activeTopics.length > 1)
        '${activeTopics.length} Kategori'
      else
        'Akademi Havuzu',
      if (difficulty != null) difficulty.label,
      if (bloom != null) bloom.label,
    ];
    _beginRound(
      title: parts.join(' · '),
      cfg: RoundSetup(
        topic: activeTopics.length == 1 ? activeTopics.first : Topic.mixed,
        selectedTopics: activeTopics,
        difficulty: difficulty,
        format: format,
        mode: mode,
        questionCount: picked.length,
      ),
      questions: picked,
    );
    return true;
  }

  bool startTopicPractice(Topic topic, {int count = 10, Difficulty? difficulty, GameMode mode = GameMode.classic}) {
    final cfg = RoundSetup(
      topic: topic,
      selectedTopics: topic == Topic.mixed ? const {} : {topic},
      difficulty: difficulty,
      mode: mode,
      questionCount: count,
    );
    return startConfiguredRound(
      customTitle: '${topic.label} · Odak Çalışması',
      overrideSetup: cfg,
    );
  }

  void startDuelTournament(
    List<String> players, {
    Topic topic = Topic.mixed,
    Set<Topic>? topics,
    int perPlayer = 3,
  }) {
    final cleanNames = players.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (cleanNames.length < 2) return;
    final count = cleanNames.length * perPlayer;
    final cfg = RoundSetup(
      topic: topic,
      selectedTopics: topics ?? const {},
      mode: GameMode.classic,
      format: QuestionFormat.multipleChoice,
      questionCount: count,
      duelPlayerNames: cleanNames,
    );
    startConfiguredRound(
      customTitle: 'Düello Turnuvası (${cleanNames.join(" vs ")})',
      overrideSetup: cfg,
    );
  }

  /// Özel oda: aynı oda numarası aynı soruları üretir. İki ya da daha çok
  /// oyuncu varsa aynı cihazda sırayla oynanır.
  bool startOdaRound(OdaAyari oda, List<String> oyuncular) {
    final adlar = oyuncular.map((e) => e.trim()).where((e) => e.isNotEmpty).take(10).toList();
    final cfg = RoundSetup(
      topic: oda.kategori,
      mode: GameMode.classic,
      format: QuestionFormat.multipleChoice,
      questionCount: oda.soruSayisi * max(1, adlar.length),
      secondsPerQuestion: oda.sure,
      duelPlayerNames: adlar.length >= 2 ? adlar : const [],
    );
    return startConfiguredRound(customTitle: 'Özel Oda ${oda.kod}', overrideSetup: cfg, seed: oda.tohum);
  }

  /// Bire Bir ya da Çoklu: bilgisayar rakiplerine karşı.
  bool startRakipMaci({
    required List<String> rakipler,
    Topic topic = Topic.mixed,
    Set<Topic>? topics,
    int soru = 7,
    int sure = 20,
  }) {
    final cfg = RoundSetup(
      topic: topic,
      selectedTopics: topics ?? const {},
      mode: GameMode.classic,
      format: QuestionFormat.multipleChoice,
      questionCount: soru,
      secondsPerQuestion: sure,
      rivalNames: rakipler,
    );
    return startConfiguredRound(
      customTitle: rakipler.length == 1 ? 'Bire Bir · ${rakipler.first}' : 'Çoklu Oda (${rakipler.length + 1} kişi)',
      overrideSetup: cfg,
    );
  }

  /// Zirve Merdiveni için 15 soru: 5 kolay, 5 orta, 5 zor; hepsi dört
  /// seçenekli metin sorusu. Ek olarak her zorluktan birer yedek soru
  /// (soru değiştirme jokeri için) döner.
  ({List<Question> sorular, Map<Difficulty, Question> yedek})? zirveSorulari({
    Topic topic = Topic.mixed,
    Set<Topic>? topics,
    int? seed,
  }) {
    final rng = Random(seed ?? DateTime.now().microsecondsSinceEpoch);
    final sorular = <Question>[];
    final yedek = <Difficulty, Question>{};
    for (final d in Difficulty.values) {
      final cfg = RoundSetup(
        topic: topic,
        selectedTopics: topics ?? const {},
        difficulty: d,
        mode: GameMode.classic,
        format: QuestionFormat.text,
        questionCount: 12,
      );
      final aday = sampleQuestions(cfg, seed: rng.nextInt(1 << 30))
          .where((q) =>
              q.options.length == 4 &&
              q.visual == null &&
              q.activity == null &&
              q.responseType == ResponseType.choice)
          .where((q) => sorular.every((x) => x.id != q.id))
          .toList();
      if (aday.length < 6) return null;
      sorular.addAll(aday.take(5));
      yedek[d] = aday[5];
    }
    return (sorular: sorular, yedek: yedek);
  }

  void zirveKaydet({required int kazanc, required int basamak}) {
    zirveEnIyi = max(zirveEnIyi, kazanc);
    zirveEnUstBasamak = max(zirveEnUstBasamak, basamak);
    xp += basamak * 15;
    notifyListeners();
    unawaited(_savePersistedState());
  }

  int etkinlikDenemesi(Etkinlik e) => etkinlikDenemeleri[e.anahtar] ?? 0;

  bool startEtkinlik(Etkinlik e) {
    if (etkinlikDenemesi(e) >= e.hak) return false;
    final cfg = RoundSetup(
      topic: e.tema.konu,
      mode: GameMode.classic,
      format: QuestionFormat.multipleChoice,
      questionCount: e.soruSayisi,
      secondsPerQuestion: 20,
    );
    final ok = startConfiguredRound(customTitle: 'Etkinlik · ${e.tema.ad}', overrideSetup: cfg, seed: e.tohum + etkinlikDenemesi(e));
    if (ok) {
      etkinlikDenemeleri[e.anahtar] = etkinlikDenemesi(e) + 1;
      _aktifEtkinlik = e.anahtar;
      unawaited(_savePersistedState());
    }
    return ok;
  }

  void startQuestionPractice(Question question) {
    _beginRound(
      title: question.lesson ?? question.category.label,
      cfg: RoundSetup(mode: GameMode.training, topic: question.category, questionCount: 1),
      questions: [question.shuffled(_rng)],
    );
  }

  void startPackRound(QuestionPack pack, {int? maxQuestions}) {
    if (pack.questions.isEmpty) return;
    final int targetCount = maxQuestions ??
        (pack.questions.length > 25 ? setup.questionCount.clamp(10, 30) : pack.questions.length);
    final qs = _pickRandomQuestions(pack.questions, targetCount, _rng);
    if (qs.isEmpty) return;
    _beginRound(
      title: pack.title,
      cfg: RoundSetup(mode: setup.mode, questionCount: qs.length),
      questions: qs,
    );
  }

  bool startStudyProfileRound(StudyProfile profile) {
    final cfg = RoundSetup(
      topic: Topic.exam,
      exam: profile.exam,
      lesson: profile.lesson,
      difficulty: profile.difficulty,
      mode: GameMode.classic,
      questionCount: profile.questionCount,
    );
    return startConfiguredRound(customTitle: profile.title, overrideSetup: cfg);
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
    round.creationResponse = '';
    round.hiddenOptions = {};
    switch (round.setup.mode) {
      case GameMode.training:
        round.totalTimerSeconds = 0;
        round.remainingSeconds = 0;
        break;
      case GameMode.classic:
        final q = round.questions.isNotEmpty ? round.current : null;
        final needsExtra = q != null &&
            (q.activity != null ||
                q.multiSelect != null ||
                q.responseType == ResponseType.fill);
        final baseSec = round.setup.liveVoiceHost
            ? 35
            : (round.setup.secondsPerQuestion ?? 15);
        round.totalTimerSeconds = needsExtra ? baseSec + 10 : baseSec;
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
      if (r.needsCreation) return;
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
        r.current.responseType != ResponseType.choice ||
        r.current.options.length < 4) {
      return false;
    }
    final wrongIndices = List.generate(r.current.options.length, (i) => i)
      ..remove(r.current.answer)
      ..shuffle(_rng);
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
  bool saveCreationResponse(String value) {
    final r = activeRound;
    if (r == null || r.finished || r.revealed || !r.needsCreation || value.trim().isEmpty) return false;
    r.creationResponse = value.trim();
    creationPortfolio[r.current.id] = r.creationResponse;
    unawaited(_savePersistedState());
    notifyListeners();
    if (r.setup.liveVoiceHost) unawaited(_runLiveVoiceForCurrentQuestion());
    return true;
  }

  void submitMultiple(Set<int> selection) {
    final r = activeRound;
    if (r == null || r.finished || r.revealed || r.needsCreation || selection.isEmpty) return;
    final task = r.current.multiSelect;
    if (task == null || selection.any((i) => i < 0 || i >= task.options.length)) return;
    _commitAnswer(round: r, question: r.current, isCorrect: task.matches(selection),
        submittedSequence: selection.toList()..sort());
  }

  void submitWrittenAnswer(String value) {
    final r = activeRound;
    if (r == null || r.finished || r.revealed || r.needsCreation ||
        r.current.responseType != ResponseType.fill || value.trim().isEmpty) {
      return;
    }
    _commitAnswer(round: r, question: r.current, isCorrect: r.current.acceptsWritten(value),
        writtenResponse: value.trim());
  }

  void submitChoice(int? choiceIndex, {String? spokenTranscript}) {
    final r = activeRound;
    if (r == null || r.revealed || r.finished) return;
    final q = r.current;
    if (r.needsCreation || (choiceIndex != null &&
        (q.responseType == ResponseType.fill ||
         q.responseType == ResponseType.multiSelect ||
         q.isSlider ||
         q.isAnagram ||
         choiceIndex < 0 ||
         choiceIndex >= q.options.length))) {
      return;
    }
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

  void submitSliderAnswer(int estimate) {
    final r = activeRound;
    if (r == null || r.revealed || r.finished || r.needsCreation) return;
    final q = r.current;
    final act = q.activity;
    if (act == null || act.kind != ActivityKind.slider) return;
    final isCorrect = act.matchesSlider(estimate);
    final unitSuffix = act.sliderUnit.isNotEmpty ? ' ${act.sliderUnit}' : '';
    _commitAnswer(
      round: r,
      question: q,
      isCorrect: isCorrect,
      selectedOption: isCorrect ? q.answer : -1,
      writtenResponse: '$estimate$unitSuffix',
    );
  }

  void submitAnagramAnswer(String word) {
    final r = activeRound;
    if (r == null || r.revealed || r.finished || r.needsCreation) return;
    final q = r.current;
    final act = q.activity;
    if (act == null || act.kind != ActivityKind.anagram || word.trim().isEmpty) return;
    final isCorrect = act.matchesAnagram(word);
    _commitAnswer(
      round: r,
      question: q,
      isCorrect: isCorrect,
      selectedOption: isCorrect ? q.answer : -1,
      writtenResponse: word.trim(),
    );
  }

  /// Bilgisayar rakipleri bu soruyu kendi hızlarında cevaplar; puanlama
  /// oyuncununkiyle aynı kuralı izler.
  void _simulateRivals(ActiveRound round, Question question) {
    for (var i = 0; i < round.setup.rivalNames.length; i++) {
      final hardness = switch (question.difficulty) {
        Difficulty.easy => 0.12,
        Difficulty.medium => 0.0,
        Difficulty.hard => -0.15,
      };
      final knows = round.rivalRng.nextDouble() < (round.rivalSkill(i) + hardness).clamp(0.2, 0.95);
      if (knows) {
        round.rivalStreaks[i]++;
        final speed = (round.rivalRng.nextDouble() * 0.8 + 0.1);
        final speedBonus = round.totalTimerSeconds > 0 ? (speed * 45).round() : 20;
        round.rivalScores[i] += question.difficulty.basePoints + speedBonus + min(round.rivalStreaks[i] * 15, 90);
        round.rivalCorrects[i]++;
      } else {
        round.rivalStreaks[i] = 0;
      }
    }
  }

  void _commitAnswer({
    required ActiveRound round,
    required Question question,
    required bool isCorrect,
    int? selectedOption,
    List<int>? submittedSequence,
    String? spokenTranscript,
    String? writtenResponse,
  }) {
    if (round.needsCreation) return;
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

    _simulateRivals(round, question);

    round.answers.add(
      AnswerRecord(
        question: question,
        selectedOption: selectedOption,
        writtenResponse: writtenResponse ?? (round.creationResponse.isEmpty ? null : round.creationResponse),
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
    final etkinlik = _aktifEtkinlik;
    _aktifEtkinlik = null;
    if (etkinlik != null && r.title.startsWith('Etkinlik · ')) {
      etkinlikEnIyi[etkinlik] = max(etkinlikEnIyi[etkinlik] ?? 0, r.totalScore);
    }

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
    } else if (r.hasRivals) {
      standings.add({'name': 'Sen', 'score': r.totalScore, 'correct': correctCount});
      for (var i = 0; i < r.setup.rivalNames.length; i++) {
        standings.add({'name': r.setup.rivalNames[i], 'score': r.rivalScores[i], 'correct': r.rivalCorrects[i]});
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

  Future<void> narrateCurrentQuestion() async {
    final r = activeRound;
    if (r == null) return;
    if (r.setup.liveVoiceHost && !r.revealed) {
      stopLiveVoiceCycle();
      await _runLiveVoiceForCurrentQuestion();
    } else {
      await _speakQuestion(r, ++_liveToken, allowRevealed: true);
    }
  }

  Future<void> _speakQuestion(ActiveRound round, int token, {bool allowRevealed = false}) async {
    final index = round.currentIndex;
    for (final segment in QuizNarration.questionSegments(round.current, index + 1,
        creationSubmitted: round.creationResponse.isNotEmpty)) {
      if (_liveToken != token || activeRound != round || round.currentIndex != index ||
          (!allowRevealed && round.revealed) || round.finished || round.paused) return;
      await _speakInLanguage(segment.text, segment.language, wait: true);
    }
  }

  Future<bool> _speakInLanguage(
    String text,
    String language, {
    required bool wait,
    double? rateOverride,
  }) =>
      NativeBridge.speak(
        text,
        language: language,
        rate: rateOverride ?? (language.startsWith('tr') ? ttsSpeechRate : 0.92),
        awaitCompletion: wait,
      );

  Future<void> speakActivityAudio(
    Question q, {
    double? rate,
    String? languageOverride,
  }) async {
    final act = q.activity;
    if (act == null) return;
    final text = act.transcript ?? q.text;
    final lang = languageOverride ?? act.language ?? 'tr-TR';
    await _speakInLanguage(text, lang, wait: false, rateOverride: rate);
  }

  Future<String?> listenOnceAndResolveCurrentQuestion({bool isPronunciation = false}) async {
    final r = activeRound;
    if (r == null || r.revealed || r.needsCreation ||
        r.current.responseType == ResponseType.fill ||
        r.current.responseType == ResponseType.multiSelect ||
        r.current.isSlider ||
        r.current.isAnagram) {
      return null;
    }
    final token = ++_liveToken;
    final question = r.current;
    bool active() => token == _liveToken && activeRound == r &&
        r.current == question && !r.finished && !r.revealed && !r.paused;
    final hasPerm = await NativeBridge.requestMicPermission();
    if (!active()) return null;
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
    final lang = question.isPronunciation
        ? (question.activity?.language ?? 'en-US')
        : 'tr-TR';
    try {
      await NativeBridge.startListening(language: lang);
      final ev = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => const VoiceEvent(type: 'error', errorMessage: 'Dinleme zaman aşımına uğradı.'),
      );
      if (!active()) return null;
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
        final msg = question.isPronunciation
            ? 'Tanınan sözcükler: “${ev.text}”. Örnekteki tüm sözcükleri aynı sırada söyle.'
            : question.isInteractiveSequence
                ? 'Öğe numaralarını sırasıyla söyle.'
                : '“${ev.text}” bir seçenekle eşleşmedi. Seçeneği ya da harfini söyle.';
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
    if (r == null || !r.setup.liveVoiceHost || r.finished || r.paused || r.revealed || r.needsCreation) return;
    final token = ++_liveToken;
    liveError = null;
    liveTranscript = '';
    livePreview = '';

    if (!skipReading) {
      livePhase = LiveVoicePhase.speakingQuestion;
      notifyListeners();
      await _speakQuestion(r, token);
      if (_liveToken != token || activeRound != r || r.revealed || r.paused || r.finished) return;
    }

    if (r.current.responseType == ResponseType.fill ||
        r.current.multiSelect != null ||
        r.current.isSlider ||
        r.current.isAnagram) {
      livePhase = LiveVoicePhase.idle;
      notifyListeners();
      return;
    }
    final hasPerm = await NativeBridge.requestMicPermission();
    if (_liveToken != token || activeRound != r || r.revealed || r.paused || r.finished) return;
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
    final pending = _pendingVoiceCompleter;
    _pendingVoiceCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const VoiceEvent(type: 'error', errorMessage: 'Dinleme sona erdi.'));
    }
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

  void updateStudyProfile(StudyProfile updated) {
    final idx = studyProfiles.indexWhere((p) => p.id == updated.id);
    if (idx < 0) {
      addStudyProfile(updated);
      return;
    }
    final next = List<StudyProfile>.of(studyProfiles);
    next[idx] = updated;
    studyProfiles = next;
    notifyListeners();
    unawaited(_savePersistedState());
  }

  bool isInReviewDeck(Question q) =>
      reviewDeck.any((c) => c.question.poolKey == q.poolKey);

  void addQuestionToReviewDeck(Question q) {
    if (isInReviewDeck(q)) return;
    reviewDeck.insert(
      0,
      ReviewCard(
        question: q,
        box: 0,
        attempts: 0,
        correct: 0,
        due: DateTime.now(),
      ),
    );
    NativeBridge.playSfx('tick', enabled: sfxEnabled, haptics: hapticsEnabled, volume: 0.35);
    notifyListeners();
    unawaited(_savePersistedState());
  }

  void removeReviewCard(String questionId) {
    final before = reviewDeck.length;
    reviewDeck.removeWhere((c) => c.question.id == questionId);
    if (reviewDeck.length != before) {
      notifyListeners();
      unawaited(_savePersistedState());
    }
  }

  /// 3D Kart Çalışması sırasında tekil soru sonucunu Leitner kutularına işler.
  void recordFlashcardReview(Question q, bool remembered) {
    _updateReviewDeck(q, remembered);
    playedQuestionIds.add(q.id);
    categoryAnswered[q.category.label] = (categoryAnswered[q.category.label] ?? 0) + 1;
    if (remembered) {
      categoryCorrect[q.category.label] = (categoryCorrect[q.category.label] ?? 0) + 1;
      xp += 5;
    }
    NativeBridge.playSfx(
      remembered ? 'correct' : 'wrong',
      enabled: sfxEnabled,
      haptics: hapticsEnabled,
      volume: 0.45,
    );
    notifyListeners();
    unawaited(_savePersistedState());
  }

  bool deleteOfflinePack(String packId) {
    if (packId.startsWith('builtin_sb_')) return false;
    final idx = offlinePacks.indexWhere((p) => p.id == packId);
    if (idx < 0) return false;
    offlinePacks.removeAt(idx);
    notifyListeners();
    unawaited(_savePersistedState());
    return true;
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
  static final _legacyPack = RegExp(r'^astra-(quant|science|culture|applied)-0[1-5]$');
  static final _legacyQuestion = RegExp(r'^mb100k_astra_[0-9a-f]{20}$');

  QuestionPack? _readPersonalPack(Map raw) {
    final data = Map<String, dynamic>.from(raw);
    final id = data['id'] ?? data['packID'];
    if (id is String && id.startsWith('builtin_sb_')) return null;
    if (id is String && _legacyPack.hasMatch(id) && data['questions'] is List) {
      final retained = (data['questions'] as List).whereType<Map>().where((q) {
        final questionId = q['id'] ?? q['contentID'];
        return questionId is! String || !_legacyQuestion.hasMatch(questionId);
      }).toList();
      if (retained.isEmpty) return null;
      data['questions'] = retained;
    }
    return QuestionPack.fromJson(data);
  }

  Future<String> importJsonQuestionPacks() async {
    final files = await NativeBridge.pickFiles(mimeType: '*/*', allowMultiple: true);
    if (files.isEmpty) return 'Dosya seçilmedi.';

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
          final personal = _readPersonalPack(decoded);
          if (personal == null) continue;
          pack = personal;
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
          if (!AdvancedCatalog.hasId(q.id) && !_loadedIds.contains(q.id) && _poolKeys.add(q.poolKey)) {
            _loadedIds.add(q.id);
            _allQuestions.add(q);
            _countPersonalQuestion(q);
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
    if (pack.questions is FamilyQuestions) return false;
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
    creationPortfolio.clear();
    reviewDeck.clear();
    history.clear();
    notifyListeners();
    await _savePersistedState();
  }

  // --- Badges ---
  List<ArenaBadgeInfo> get badges {
    final hasFlawless =
        history.any((h) => h.totalQuestions >= 5 && h.correctCount == h.totalQuestions);
    final hasVoiceRound = history.any((h) => h.wasLiveVoice);
    final hasDuelRound = history.any((h) => h.duelStandings.isNotEmpty);
    final bestRoundStreak = history.fold<int>(0, (acc, h) => max(acc, h.maxStreak));
    final activeCategories = Topic.poolCategories
        .where((t) => (categoryAnswered[t.label] ?? 0) > 0)
        .length;
    final totalCategories = Topic.poolCategories.length;
    final solvedCount = playedQuestionIds.length;

    return [
      ArenaBadgeInfo(
        id: 'first_step',
        title: 'İlk Adım',
        description: 'İlk bilgi turunu tamamla',
        iconKind: IconDataCompat.spark,
        unlocked: history.isNotEmpty,
        current: min(history.length, 1),
        target: 1,
        group: 'Genel',
      ),
      ArenaBadgeInfo(
        id: 'curious',
        title: 'Meraklı Kaşif',
        description: 'En az 50 soruyu yanıtla',
        iconKind: IconDataCompat.curious,
        unlocked: solvedCount >= 50,
        current: min(solvedCount, 50),
        target: 50,
        group: 'Akademi',
      ),
      ArenaBadgeInfo(
        id: 'hunter',
        title: 'Bilgi Avcısı',
        description: '250 farklı soruyu keşfet',
        iconKind: IconDataCompat.hunter,
        unlocked: solvedCount >= 250,
        current: min(solvedCount, 250),
        target: 250,
        group: 'Akademi',
      ),
      ArenaBadgeInfo(
        id: 'encyclopedia',
        title: 'Yaşayan Ansiklopedi',
        description: '1.000 soruyu tamamla',
        iconKind: IconDataCompat.encyclopedia,
        unlocked: solvedCount >= 1000,
        current: min(solvedCount, 1000),
        target: 1000,
        group: 'Akademi',
      ),
      ArenaBadgeInfo(
        id: 'flawless',
        title: 'Kusursuz Tur',
        description: 'En az 5 soruluk turu %100 doğrulukla bitir',
        iconKind: IconDataCompat.flawless,
        unlocked: hasFlawless,
        current: hasFlawless ? 1 : 0,
        target: 1,
        group: 'Ustalık',
      ),
      ArenaBadgeInfo(
        id: 'streak_10',
        title: 'Ateşli Seri',
        description: 'Tek turda üst üste 10 doğru yanıt ver',
        iconKind: IconDataCompat.streak,
        unlocked: bestRoundStreak >= 10,
        current: min(bestRoundStreak, 10),
        target: 10,
        group: 'Ustalık',
      ),
      ArenaBadgeInfo(
        id: 'master',
        title: 'Bilgi Ustası',
        description: 'Seviye 5 ve üzerine ulaş',
        iconKind: IconDataCompat.master,
        unlocked: level >= 5,
        current: min(level, 5),
        target: 5,
        group: 'Ustalık',
      ),
      ArenaBadgeInfo(
        id: 'sage',
        title: 'İstanbul Bilgesi',
        description: 'Seviye 15 unvanına yüksel',
        iconKind: IconDataCompat.sage,
        unlocked: level >= 15,
        current: min(level, 15),
        target: 15,
        group: 'Ustalık',
      ),
      ArenaBadgeInfo(
        id: 'explorer_5',
        title: 'Çok Yönlü Zihin',
        description: 'En az 5 farklı kategoride soru çöz',
        iconKind: IconDataCompat.explorer5,
        unlocked: activeCategories >= 5,
        current: min(activeCategories, 5),
        target: 5,
        group: 'Akademi',
      ),
      ArenaBadgeInfo(
        id: 'explorer_23',
        title: '23 Alan Kaşifi',
        description: 'Tüm $totalCategories kategorinin her birinde soru çöz',
        iconKind: IconDataCompat.explorer23,
        unlocked: activeCategories >= totalCategories,
        current: activeCategories,
        target: totalCategories,
        group: 'Akademi',
      ),
      ArenaBadgeInfo(
        id: 'zirve_mid',
        title: 'Zirve Yolcusu',
        description: 'Zirve Merdiveni\'nde 5. barajı geç',
        iconKind: IconDataCompat.zirveMid,
        unlocked: zirveEnUstBasamak >= 5,
        current: min(zirveEnUstBasamak, 5),
        target: 5,
        group: 'Zirve',
      ),
      ArenaBadgeInfo(
        id: 'zirve_top',
        title: 'Zirve Şampiyonu',
        description: 'Zirve Merdiveni\'nde 10. barajı aş',
        iconKind: IconDataCompat.zirveTop,
        unlocked: zirveEnUstBasamak >= 10,
        current: min(zirveEnUstBasamak, 10),
        target: 10,
        group: 'Zirve',
      ),
      ArenaBadgeInfo(
        id: 'collector',
        title: 'Koleksiyoncu',
        description: 'Bilgi Defterine 5 soru kaydet',
        iconKind: IconDataCompat.collector,
        unlocked: savedBookmarks.length >= 5,
        current: min(savedBookmarks.length, 5),
        target: 5,
        group: 'Akademi',
      ),
      ArenaBadgeInfo(
        id: 'daily_habit',
        title: 'İstikrar Yıldızı',
        description: '3 gün üst üste çalışma serisi yakala',
        iconKind: IconDataCompat.dailyHabit,
        unlocked: dailyStreak >= 3,
        current: min(dailyStreak, 3),
        target: 3,
        group: 'Genel',
      ),
      ArenaBadgeInfo(
        id: 'voice_star',
        title: 'Sesli Şampiyon',
        description: 'Canlı Sesli Yarışma turu tamamla',
        iconKind: IconDataCompat.voiceStar,
        unlocked: hasVoiceRound,
        current: hasVoiceRound ? 1 : 0,
        target: 1,
        group: 'Genel',
      ),
      ArenaBadgeInfo(
        id: 'duel_king',
        title: 'Düello Ustası',
        description: 'Çok oyunculu bir düello turnuvası bitir',
        iconKind: IconDataCompat.duelKing,
        unlocked: hasDuelRound,
        current: hasDuelRound ? 1 : 0,
        target: 1,
        group: 'Genel',
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
        'creationPortfolio': Map<String, String>.of(creationPortfolio),
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
        'uiThemeRev': _currentUiThemeRev,
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
        'etkinlikDenemeleri': etkinlikDenemeleri,
        'etkinlikEnIyi': etkinlikEnIyi,
        'zirveEnIyi': zirveEnIyi,
        'zirveEnUstBasamak': zirveEnUstBasamak,
      };

  void _applyStateMap(Map<String, dynamic> map) {
    zirveEnIyi = (map['zirveEnIyi'] as num?)?.toInt() ?? 0;
    zirveEnUstBasamak = (map['zirveEnUstBasamak'] as num?)?.toInt() ?? 0;
    for (final (hedef, ad) in [(etkinlikDenemeleri, 'etkinlikDenemeleri'), (etkinlikEnIyi, 'etkinlikEnIyi')]) {
      hedef.clear();
      final m = map[ad];
      if (m is Map) {
        for (final e in m.entries) {
          hedef[e.key.toString()] = (e.value as num?)?.toInt() ?? 0;
        }
      }
    }
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

    creationPortfolio.clear();
    final portfolio = map['creationPortfolio'];
    if (portfolio is Map) {
      for (final entry in portfolio.entries) {
        if (entry.key is String && entry.value is String && (entry.value as String).trim().isNotEmpty) {
          creationPortfolio[entry.key as String] = entry.value as String;
        }
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

    _allQuestions.clear();
    _loadedIds.clear();
    _poolKeys.clear();
    _recomputePoolStats();
    lastImportedPackId = null;
    lastImportedQuestionIds = [];
    offlinePacks
      ..removeWhere((p) => !p.id.startsWith('builtin_sb_'))
      ..insertAll(
        0,
        ((map['offlinePacks'] as List?) ?? const [])
            .whereType<Map>()
            .map(_readPersonalPack).whereType<QuestionPack>(),
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

    final savedThemeRev = (map['uiThemeRev'] as num?)?.toInt() ?? 0;
    if (savedThemeRev < _currentUiThemeRev) {
      wallpaperId = 'istanbul_bogaz';
      wallpaperClarity = WallpaperClarity.vivid;
    } else {
      wallpaperId = map['wallpaperId']?.toString() ?? 'istanbul_bogaz';
      wallpaperClarity = WallpaperClarity.values.firstWhere(
        (c) => c.name == map['wallpaperClarity'],
        orElse: () => WallpaperClarity.vivid,
      );
    }
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

  Future<void> _pendingSave = Future<void>.value();

  Future<void> _savePersistedState() {
    if (!persistToDisk) return Future<void>.value();
    _pendingSave = _pendingSave.then((_) async {
      try {
        final file = await _stateFile();
        final pending = File('${file.path}.tmp');
        await pending.writeAsString(jsonEncode(_buildStateMap()), flush: true);
        await pending.rename(file.path);
      } on FileSystemException catch (error) {
        debugPrint('Bilgili ilerlemesi kaydedilemedi: $error');
      }
    });
    return _pendingSave;
  }

  @override
  void dispose() {
    _stopRoundTimer();
    _voiceSub?.cancel();
    super.dispose();
  }
}
