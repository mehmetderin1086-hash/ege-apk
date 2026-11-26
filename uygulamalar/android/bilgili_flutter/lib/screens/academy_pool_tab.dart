import 'dart:math';
import 'package:flutter/material.dart';
import '../data/advanced/catalog.dart';
import '../models/quiz_models.dart';
import '../state/arena_controller.dart';
import '../state/question_browser.dart';
import '../theme/arena_design.dart';
import '../widgets/question_renderers.dart';

class AcademyPoolTab extends StatefulWidget {
  final ArenaController controller;
  const AcademyPoolTab({super.key, required this.controller});

  @override
  State<AcademyPoolTab> createState() => _AcademyPoolTabState();
}

enum _PackGroup {
  all('Tümü'),
  personal('Kişisel'),
  topic('Konular'),
  bloom('Bloom'),
  general('Genel');

  final String label;
  const _PackGroup(this.label);
}

class _AcademyPoolTabState extends State<AcademyPoolTab> {
  int _section = 0; // 0: Havuz, 1: Tekrar, 2: Defterim, 3: Paketler, 4: Profiller

  // Havuz filtreleri
  String _query = '';
  final _queryController = TextEditingController();
  final Set<Topic> _filterTopics = {};
  QuestionFormat _filterFormat = QuestionFormat.mixed;
  Difficulty? _filterDifficulty;
  PoolStatusFilter _statusFilter = PoolStatusFilter.all;
  bool _hideReported = true;
  bool _filtersExpanded = true;
  PoolCollection _collection = PoolCollection.all;
  BloomLevel? _bloom;

  Object? _searchKey;
  BrowserPageTask? _pageTask;
  Future<BrowserPage>? _pageFuture;
  final List<BrowserCursor> _pages = [firstBrowserPage];

  // Soru kartı içi etkileşim durumu
  final Set<String> _expandedQuestionIds = {};
  final Map<String, int> _selfTestSelections = {};
  final Set<String> _revealedAnswers = {};

  // Tekrar sekmesi filtreleri
  int? _reviewBoxFilter;
  bool _reviewOnlyDue = false;
  Topic? _reviewTopicFilter;
  final Set<String> _expandedReviewIds = {};

  // Defterim filtreleri
  String _bookmarkQuery = '';
  final _bookmarkSearchCtrl = TextEditingController();
  Topic? _bookmarkTopicFilter;
  final Set<String> _expandedBookmarkIds = {};

  // Paketler filtreleri
  String _packQuery = '';
  final _packSearchCtrl = TextEditingController();
  _PackGroup _packGroup = _PackGroup.all;
  int _packPlayCount = 15;

  static const _sayisalBundle = {
    Topic.mathematics,
    Topic.physics,
    Topic.chemistry,
    Topic.biology,
    Topic.statistics,
  };
  static const _sozelBundle = {
    Topic.history,
    Topic.geography,
    Topic.literature,
    Topic.socialScience,
  };
  static const _bilimTekBundle = {
    Topic.science,
    Topic.technology,
    Topic.computing,
    Topic.engineering,
    Topic.research,
  };
  static const _kulturSanatBundle = {
    Topic.culture,
    Topic.art,
    Topic.music,
    Topic.cinema,
    Topic.sport,
    Topic.nature,
  };

  @override
  void dispose() {
    _pageTask?.cancel();
    _queryController.dispose();
    _bookmarkSearchCtrl.dispose();
    _packSearchCtrl.dispose();
    super.dispose();
  }

  String _formatNum(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    final buf = StringBuffer();
    final rem = s.length % 3;
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (i - rem) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  int get _activeFilterCount {
    var c = 0;
    if (_query.trim().isNotEmpty) c++;
    if (_collection != PoolCollection.all) c++;
    if (_bloom != null) c++;
    if (_filterDifficulty != null) c++;
    if (_statusFilter != PoolStatusFilter.all) c++;
    if (_filterTopics.isNotEmpty) c++;
    if (_filterFormat != QuestionFormat.mixed) c++;
    return c;
  }

  void _resetAllPoolFilters() {
    setState(() {
      _query = '';
      _queryController.clear();
      _collection = PoolCollection.all;
      _bloom = null;
      _filterDifficulty = null;
      _statusFilter = PoolStatusFilter.all;
      _filterTopics.clear();
      _filterFormat = QuestionFormat.mixed;
    });
  }

  String _sceneForSection() => switch (_section) {
        0 => 'academy',
        1 => 'kiz_kulesi',
        2 => 'notebook',
        3 => 'galata',
        _ => 'duel_stage',
      };

  void _openFlashcardStudy(
    BuildContext context, {
    required List<Question> questions,
    required String title,
    required bool leitnerMode,
  }) {
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kart çalışması için soru bulunamadı.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _Studio3DFlashcardSheet(
        controller: widget.controller,
        questions: questions,
        title: title,
        leitnerMode: leitnerMode,
      ),
    );
  }

  void _openAllCategoriesSheet(BuildContext context, ArenaController ctrl) {
    var catQuery = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudioPalette.navyDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        side: BorderSide(color: StudioPalette.gold, width: 1.6),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final allTopics = ctrl.availableTopics.where((t) {
            if (catQuery.trim().isEmpty) return true;
            return t.label.toLowerCase().contains(catQuery.trim().toLowerCase());
          }).toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            minChildSize: 0.55,
            maxChildSize: 0.94,
            builder: (ctx, scrollCtrl) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.grid_view_rounded, color: StudioPalette.goldBright, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tüm Kategoriler (${ctrl.availableTopics.length})',
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            color: StudioPalette.goldBright,
                          ),
                        ),
                      ),
                      if (_filterTopics.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() => _filterTopics.clear());
                            setSheet(() {});
                          },
                          child: const Text('Temizle'),
                        ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    onChanged: (v) => setSheet(() => catQuery = v),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Kategori ara (Matematik, Tarih, Biyoloji...)',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 12.5),
                      prefixIcon: const Icon(Icons.search_rounded, color: StudioPalette.gold, size: 19),
                      filled: true,
                      fillColor: StudioPalette.navyTop.withValues(alpha: 0.58),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: StudioPalette.gold.withValues(alpha: 0.32)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: StudioPalette.gold, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollCtrl,
                      itemCount: allTopics.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.72,
                      ),
                      itemBuilder: (ctx, i) {
                        final t = allTopics[i];
                        final selected = _filterTopics.contains(t);
                        final count = ctrl.countForTopic(t);
                        final ans = ctrl.categoryAnswered[t.label] ?? 0;
                        final cor = ctrl.categoryCorrect[t.label] ?? 0;
                        final pct = ans == 0 ? null : ((cor / ans) * 100).round();
                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (!_filterTopics.remove(t)) _filterTopics.add(t);
                            });
                            setSheet(() {});
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: selected
                                    ? [
                                        StudioPalette.gold.withValues(alpha: 0.34),
                                        StudioPalette.navyTop,
                                      ]
                                    : [
                                        StudioPalette.navyMid.withValues(alpha: 0.9),
                                        StudioPalette.night,
                                      ],
                              ),
                              border: Border.all(
                                color: selected
                                    ? StudioPalette.goldBright
                                    : t.accent.withValues(alpha: 0.42),
                                width: selected ? 1.8 : 1.1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(t.icon, size: 16, color: selected ? StudioPalette.goldBright : t.accent),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${_formatNum(count)} soru',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white.withValues(alpha: 0.72),
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      const Icon(Icons.check_circle_rounded,
                                          size: 16, color: StudioPalette.goldBright),
                                  ],
                                ),
                                const Spacer(),
                                Text(
                                  t.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                    color: selected ? StudioPalette.goldBright : Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  pct == null ? 'Henüz çözülmedi' : 'Başarı %$pct ($cor/$ans)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: pct == null
                                        ? Colors.white54
                                        : (pct >= 75 ? StudioPalette.emerald : StudioPalette.gold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Studio3DButton(
                    label: _filterTopics.isEmpty
                        ? 'Tüm Kategorileri Göster'
                        : '${_filterTopics.length} Kategoriyi Uygula',
                    icon: Icons.check_rounded,
                    expand: true,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showProfileSheet(BuildContext context, {StudyProfile? editing}) {
    ExamKind exam = editing?.exam ?? ExamKind.tyt;
    String lesson = editing?.lesson ?? ExamKind.tyt.lessons.first;
    if (!exam.lessons.contains(lesson)) lesson = exam.lessons.first;
    Difficulty diff = editing?.difficulty ?? Difficulty.medium;
    int count = editing?.questionCount ?? 10;
    final titleCtrl = TextEditingController(
      text: editing?.title ?? 'TYT Odak Çalışması',
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudioPalette.navyDark,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: StudioPalette.gold.withValues(alpha: 0.45)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final accent = widget.controller.currentWallpaper.primary;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.school_rounded, color: StudioPalette.goldBright),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          editing == null
                              ? 'Yeni Sınav Çalışma Profili'
                              : 'Çalışma Profilini Düzenle',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: StudioPalette.goldBright,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Profil Adı',
                      labelStyle: const TextStyle(color: StudioPalette.goldBright),
                      filled: true,
                      fillColor: StudioPalette.navyTop.withValues(alpha: 0.6),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: StudioPalette.gold.withValues(alpha: 0.35)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: StudioPalette.gold, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sınav Türü',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  ArenaScrollPills<ExamKind>(
                    items: ExamKind.values,
                    selected: exam,
                    labelBuilder: (e) => e.label,
                    onSelected: (e) => setSheet(() {
                      exam = e;
                      lesson = e.lessons.first;
                    }),
                    accent: accent,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ders',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  ArenaScrollPills<String>(
                    items: exam.lessons,
                    selected: lesson,
                    labelBuilder: (l) => l,
                    onSelected: (l) => setSheet(() => lesson = l),
                    accent: accent,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Zorluk & Soru Sayısı',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  ArenaScrollPills<Difficulty>(
                    items: Difficulty.values,
                    selected: diff,
                    labelBuilder: (d) => d.label,
                    onSelected: (d) => setSheet(() => diff = d),
                    accent: accent,
                  ),
                  const SizedBox(height: 8),
                  ArenaScrollPills<int>(
                    items: const [5, 10, 15, 20, 30],
                    selected: count,
                    labelBuilder: (n) => '$n Soru',
                    onSelected: (n) => setSheet(() => count = n),
                    accent: accent,
                  ),
                  const SizedBox(height: 16),
                  Studio3DButton(
                    label: editing == null ? 'Profili Kaydet' : 'Değişiklikleri Kaydet',
                    icon: Icons.save_rounded,
                    expand: true,
                    onPressed: () {
                      final profile = StudyProfile(
                        id: editing?.id ?? 'prof_${DateTime.now().millisecondsSinceEpoch}',
                        title: titleCtrl.text.trim().isEmpty
                            ? '${exam.label} · $lesson'
                            : titleCtrl.text.trim(),
                        exam: exam,
                        lesson: lesson,
                        difficulty: diff,
                        questionCount: count,
                      );
                      if (editing == null) {
                        widget.controller.addStudyProfile(profile);
                      } else {
                        widget.controller.updateStudyProfile(profile);
                      }
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final accent = ctrl.currentWallpaper.primary;
    final dueCount = ctrl.dueReviewCards.length;
    final solvedPct = ctrl.totalPoolCount == 0
        ? 0.0
        : (ctrl.playedQuestionIds.length / ctrl.totalPoolCount).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArenaSceneHeader(
                title: 'Bilgi Akademisi & Havuz',
                description:
                    '${_formatNum(ctrl.totalPoolCount)} soru · Leitner tekrar · Bilgi defteri · Çevrimdışı paketler',
                scene: _sceneForSection(),
                trailing: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [StudioPalette.navyTop, StudioPalette.night],
                    ),
                    border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.7), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: StudioPalette.gold.withValues(alpha: 0.28), blurRadius: 10),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          value: max(0.03, solvedPct),
                          strokeWidth: 3.4,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          valueColor: const AlwaysStoppedAnimation<Color>(StudioPalette.goldBright),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${ctrl.playedQuestionIds.length}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: StudioPalette.goldBright,
                              height: 1.0,
                            ),
                          ),
                          const Text(
                            'çözüldü',
                            style: TextStyle(fontSize: 7.5, color: Colors.white70, height: 1.1),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 11),
              ArenaScrollPills<int>(
                items: const [0, 1, 2, 3, 4],
                selected: _section,
                labelBuilder: (idx) {
                  switch (idx) {
                    case 0:
                      return 'Havuz (${_formatNum(ctrl.totalPoolCount)})';
                    case 1:
                      return dueCount > 0
                          ? 'Tekrar ($dueCount/${ctrl.reviewDeck.length})'
                          : 'Tekrar (${ctrl.reviewDeck.length})';
                    case 2:
                      return 'Defterim (${ctrl.savedBookmarks.length})';
                    case 3:
                      return 'Paketler (${ctrl.offlinePacks.length})';
                    default:
                      return 'Profiller (${ctrl.studyProfiles.length})';
                  }
                },
                iconBuilder: (idx) {
                  switch (idx) {
                    case 0:
                      return Icons.storage_rounded;
                    case 1:
                      return Icons.replay_rounded;
                    case 2:
                      return Icons.bookmark_rounded;
                    case 3:
                      return Icons.inventory_2_rounded;
                    default:
                      return Icons.school_rounded;
                  }
                },
                onSelected: (idx) => setState(() => _section = idx),
                accent: accent,
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildActiveSection(context, ctrl, accent),
        ),
      ],
    );
  }

  Widget _buildActiveSection(BuildContext context, ArenaController ctrl, Color accent) {
    switch (_section) {
      case 0:
        return _buildQuestionPoolBrowser(context, ctrl, accent);
      case 1:
        return _buildSpacedRepetitionView(context, ctrl, accent);
      case 2:
        return _buildBookmarksView(context, ctrl, accent);
      case 3:
        return _buildPacksView(context, ctrl, accent);
      default:
        return _buildProfilesView(context, ctrl, accent);
    }
  }

  // =========================================================================
  // BÖLÜM 0: HAVUZ (224.144 SORU KEŞİF & ÇALIŞMA STÜDYOSU)
  // =========================================================================
  Widget _buildQuestionPoolBrowser(BuildContext context, ArenaController ctrl, Color accent) {
    final query = _query.trim().toLowerCase();
    final hiddenCount = _hideReported ? ctrl.reportedQuestionIds.length : 0;
    final topicsSig = Object.hashAllUnordered(_filterTopics);
    final key = (
      _collection,
      _bloom,
      _filterDifficulty,
      _statusFilter,
      topicsSig,
      _filterTopics.length,
      _filterFormat,
      query,
      _hideReported,
      ctrl.totalPoolCount,
      ctrl.playedQuestionIds.length,
      ctrl.savedBookmarks.length,
      hiddenCount,
      ctrl,
    );
    if (_searchKey != key) {
      _pageTask?.cancel();
      _pageFuture = null;
      _pages
        ..clear()
        ..add(firstBrowserPage);
      _searchKey = key;
    }
    if (_pageFuture == null) {
      _pageTask = BrowserPageTask(
        personal: ctrl.personalQuestions,
        collection: _collection,
        bloom: _bloom,
        difficulty: _filterDifficulty,
        statusFilter: _statusFilter,
        playedIds: Set<String>.of(ctrl.playedQuestionIds),
        bookmarkedKeys: ctrl.savedBookmarks.map((q) => q.poolKey).toSet(),
        topic: _filterTopics.length == 1 ? _filterTopics.first : Topic.mixed,
        topics: Set<Topic>.of(_filterTopics),
        format: _filterFormat,
        query: query,
        cursor: _pages.last,
        hidden: _hideReported ? Set.of(ctrl.reportedQuestionIds) : const {},
      );
      _pageFuture = _pageTask!.run();
    }
    return FutureBuilder<BrowserPage>(
      future: _pageFuture,
      builder: (context, snapshot) => _buildBrowserPage(context, ctrl, accent, snapshot),
    );
  }

  Widget _buildBrowserPage(
    BuildContext context,
    ArenaController ctrl,
    Color accent,
    AsyncSnapshot<BrowserPage> snapshot,
  ) {
    final waiting = snapshot.connectionState != ConnectionState.done;
    final page = waiting ? null : snapshot.data;
    final shown = page?.items ?? const <Question>[];
    final filteredPoolEstimate = ctrl.countFilteredPool(
      topics: _filterTopics.isEmpty ? null : _filterTopics,
      difficulty: _filterDifficulty,
      bloom: _bloom,
      format: _filterFormat,
      collection: _collection,
    );
    final showCounts = _collection == PoolCollection.all &&
        _bloom == null &&
        _filterDifficulty == null &&
        _statusFilter == PoolStatusFilter.all &&
        _filterFormat == QuestionFormat.mixed &&
        _query.trim().isEmpty;

    final solvedRatio = ctrl.totalPoolCount == 0
        ? 0.0
        : (ctrl.playedQuestionIds.length / ctrl.totalPoolCount).clamp(0.0, 1.0);

    return ListView.builder(
      key: ValueKey('pool_p${_pages.length}'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 108),
      itemCount: shown.length + 2,
      itemBuilder: (ctx, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Etkileşimli 3D İstatistik Şeridi (Tıklayınca filtreler!)
              ArenaGlassCard(
                tint: StudioPalette.gold,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _tappableMiniStat(
                            label: 'Toplam',
                            value: _formatNum(ctrl.totalPoolCount),
                            color: StudioPalette.goldBright,
                            active: _activeFilterCount == 0,
                            onTap: _resetAllPoolFilters,
                          ),
                        ),
                        Expanded(
                          child: _tappableMiniStat(
                            label: 'Görsel',
                            value: _formatNum(ctrl.visualQuestionCount),
                            color: const Color(0xFFFFB454),
                            active: _filterFormat == QuestionFormat.visual,
                            onTap: () => setState(() {
                              _filterFormat = _filterFormat == QuestionFormat.visual
                                  ? QuestionFormat.mixed
                                  : QuestionFormat.visual;
                            }),
                          ),
                        ),
                        Expanded(
                          child: _tappableMiniStat(
                            label: 'Çözülen',
                            value: _formatNum(ctrl.playedQuestionIds.length),
                            color: StudioPalette.emerald,
                            active: _statusFilter == PoolStatusFilter.solved,
                            onTap: () => setState(() {
                              _statusFilter = _statusFilter == PoolStatusFilter.solved
                                  ? PoolStatusFilter.all
                                  : PoolStatusFilter.solved;
                            }),
                          ),
                        ),
                        Expanded(
                          child: _tappableMiniStat(
                            label: 'Tekrar',
                            value: '${ctrl.reviewDeck.length}',
                            color: const Color(0xFFC5A3FF),
                            active: false,
                            onTap: () => setState(() => _section = 1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Studio3DProgressBar(
                      value: max(0.015, solvedRatio),
                      color: StudioPalette.gold,
                      endColor: StudioPalette.emerald,
                      height: 6,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Aktif filtre havuzu: ${_formatNum(filteredPoolEstimate)} soru',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                        Text(
                          'Keşif %${(solvedRatio * 100).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: StudioPalette.goldBright,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 2. Akıllı Arama Çubuğu + Filtre Çekmecesi Düğmesi
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: '${_formatNum(ctrl.totalPoolCount)} soru, şık veya açıklamada ara...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.48),
                          fontSize: 12.5,
                        ),
                        prefixIcon: Icon(Icons.search_rounded, color: accent, size: 20),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                                onPressed: () => setState(() {
                                  _query = '';
                                  _queryController.clear();
                                }),
                              )
                            : null,
                        filled: true,
                        fillColor: StudioPalette.navyTop.withValues(alpha: 0.58),
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: StudioPalette.gold.withValues(alpha: 0.32)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: StudioPalette.gold, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ArenaPressDepth(
                    depthOffset: 1.6,
                    child: InkWell(
                      onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: _activeFilterCount > 0
                                ? [StudioPalette.gold.withValues(alpha: 0.34), StudioPalette.navyTop]
                                : [StudioPalette.navyTop, StudioPalette.navyDark],
                          ),
                          border: Border.all(
                            color: _activeFilterCount > 0
                                ? StudioPalette.goldBright
                                : StudioPalette.gold.withValues(alpha: 0.4),
                            width: 1.3,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _filtersExpanded
                                  ? Icons.filter_list_off_rounded
                                  : Icons.tune_rounded,
                              size: 18,
                              color: StudioPalette.goldBright,
                            ),
                            if (_activeFilterCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '$_activeFilterCount',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: StudioPalette.goldBright,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              if (_activeFilterCount > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$_activeFilterCount aktif filtre uygulanıyor',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: StudioPalette.goldBright,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _resetAllPoolFilters,
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: StudioPalette.crimson.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: StudioPalette.crimson.withValues(alpha: 0.65)),
                        ),
                        child: const Text(
                          'Tümünü Sıfırla',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),

              // 3. Gelişmiş Filtre Stüdyosu (Açılır/Kapanır)
              if (_filtersExpanded) ...[
                ArenaGlassCard(
                  tint: StudioPalette.sapphire,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Zorluk Filtresi
                      const Text(
                        'Zorluk & Durum',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: StudioPalette.goldBright,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _colorFilterPill(
                              label: 'Tüm Zorluklar',
                              selected: _filterDifficulty == null,
                              color: StudioPalette.gold,
                              onTap: () => setState(() => _filterDifficulty = null),
                            ),
                            for (final d in Difficulty.values) ...[
                              const SizedBox(width: 6),
                              _colorFilterPill(
                                label: d.label,
                                selected: _filterDifficulty == d,
                                color: d.color,
                                onTap: () => setState(() {
                                  _filterDifficulty = _filterDifficulty == d ? null : d;
                                }),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      ArenaScrollPills<PoolStatusFilter>(
                        items: PoolStatusFilter.values,
                        selected: _statusFilter,
                        labelBuilder: (s) => s.label,
                        onSelected: (s) => setState(() => _statusFilter = s),
                        accent: accent,
                      ),
                      const SizedBox(height: 10),

                      // Koleksiyon & Bloom
                      const Text(
                        'Koleksiyon & Bloom Basamağı',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: StudioPalette.goldBright,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ArenaScrollPills<PoolCollection>(
                        items: const [
                          PoolCollection.all,
                          PoolCollection.highSchool,
                          PoolCollection.personal,
                        ],
                        selected: _collection,
                        labelBuilder: (c) => c.label,
                        onSelected: (c) => setState(() {
                          _collection = c;
                          if (c == PoolCollection.personal) _bloom = null;
                        }),
                        accent: accent,
                      ),
                      if (_collection != PoolCollection.personal) ...[
                        const SizedBox(height: 7),
                        ArenaScrollPills<BloomLevel?>(
                          items: [null, ...BloomLevel.values],
                          selected: _bloom,
                          labelBuilder: (b) => b?.label ?? 'Tüm Bloom basamakları',
                          onSelected: (b) => setState(() => _bloom = b),
                          accent: accent,
                        ),
                      ],
                      const SizedBox(height: 10),

                      // Çoklu Kategori Seçimi + Hızlı Alan Paketleri + Tüm 23 Kategori Izgarası
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _filterTopics.isEmpty
                                  ? 'Kategoriler (Birden fazla seçebilirsin)'
                                  : 'Seçili Kategoriler (${_filterTopics.length})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: StudioPalette.goldBright,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _openAllCategoriesSheet(context, ctrl),
                            borderRadius: BorderRadius.circular(99),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: StudioPalette.gold.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.5)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.grid_view_rounded,
                                      size: 12, color: StudioPalette.goldBright),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tüm 23 Alan',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: StudioPalette.goldBright,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _bundleQuickChip(
                              label: 'Tümü',
                              active: _filterTopics.isEmpty,
                              onTap: () => setState(() => _filterTopics.clear()),
                            ),
                            const SizedBox(width: 6),
                            _bundleQuickChip(
                              label: 'Sayısal',
                              active: _setEquals(_filterTopics, _sayisalBundle),
                              onTap: () => setState(() {
                                _filterTopics
                                  ..clear()
                                  ..addAll(_sayisalBundle);
                              }),
                            ),
                            const SizedBox(width: 6),
                            _bundleQuickChip(
                              label: 'Sözel',
                              active: _setEquals(_filterTopics, _sozelBundle),
                              onTap: () => setState(() {
                                _filterTopics
                                  ..clear()
                                  ..addAll(_sozelBundle);
                              }),
                            ),
                            const SizedBox(width: 6),
                            _bundleQuickChip(
                              label: 'Bilim & Tek',
                              active: _setEquals(_filterTopics, _bilimTekBundle),
                              onTap: () => setState(() {
                                _filterTopics
                                  ..clear()
                                  ..addAll(_bilimTekBundle);
                              }),
                            ),
                            const SizedBox(width: 6),
                            _bundleQuickChip(
                              label: 'Kültür & Sanat',
                              active: _setEquals(_filterTopics, _kulturSanatBundle),
                              onTap: () => setState(() {
                                _filterTopics
                                  ..clear()
                                  ..addAll(_kulturSanatBundle);
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _multiTopicChip(
                              label: showCounts ? 'Tümü (${_formatNum(ctrl.totalPoolCount)})' : 'Tümü',
                              selected: _filterTopics.isEmpty,
                              color: StudioPalette.gold,
                              onTap: () => setState(() => _filterTopics.clear()),
                            ),
                            const SizedBox(width: 6),
                            for (final t in ctrl.availableTopics) ...[
                              _multiTopicChip(
                                label: showCounts
                                    ? '${t.label} (${_formatNum(ctrl.countForTopic(t))})'
                                    : t.label,
                                selected: _filterTopics.contains(t),
                                color: t.accent,
                                onTap: () => setState(() {
                                  if (!_filterTopics.remove(t)) {
                                    _filterTopics.add(t);
                                  }
                                }),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ArenaScrollPills<QuestionFormat>(
                        items: QuestionFormat.sunulan,
                        selected: _filterFormat,
                        labelBuilder: (f) => f.label,
                        iconBuilder: (f) => f.icon,
                        onSelected: (f) => setState(() => _filterFormat = f),
                        accent: accent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // 4. Hızlı Çalışma Başlatıcı Çubuğu (Filtreyle Tur + 3D Kart Modu)
              Row(
                children: [
                  Expanded(
                    child: Studio3DButton(
                      label: 'Filtreyle Tur (10)',
                      icon: Icons.play_arrow_rounded,
                      variant: StudioButtonVariant.gold,
                      expand: true,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      onPressed: filteredPoolEstimate == 0
                          ? null
                          : () {
                              final ok = ctrl.startFilteredAcademyRound(
                                topics: _filterTopics.isEmpty ? null : Set<Topic>.of(_filterTopics),
                                difficulty: _filterDifficulty,
                                bloom: _bloom,
                                format: _filterFormat,
                                collection: _collection,
                                count: 10,
                              );
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Bu filtrelerle eşleşen soru bulunamadı.'),
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Studio3DButton(
                      label: '3D Kart Modu',
                      icon: Icons.style_rounded,
                      variant: StudioButtonVariant.navy,
                      shimmer: false,
                      expand: true,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      onPressed: shown.isEmpty
                          ? null
                          : () => _openFlashcardStudy(
                                context,
                                questions: shown,
                                title: 'Havuz 3D Kart Çalışması',
                                leitnerMode: false,
                              ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 5. Sonuç Özeti & Gizli Soru Anahtarı
              Row(
                children: [
                  Expanded(
                    child: Text(
                      waiting
                          ? 'Sorular hazırlanıyor…'
                          : snapshot.hasError
                              ? 'Soru araması tamamlanamadı.'
                              : shown.isEmpty
                                  ? 'Eşleşen soru bulunamadı.'
                                  : 'Sayfa ${_pages.length} · ${shown.length} soru gösteriliyor',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() => _hideReported = !_hideReported),
                    child: Text(
                      _hideReported ? 'Gizlenenleri Göster' : 'Gizlenenleri Sakla',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          );
        }

        // Sayfalama alt barı
        if (index == shown.length + 1) {
          if (waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(color: StudioPalette.gold),
            );
          }
          if (_pages.length == 1 && page?.hasMore != true) return const SizedBox(height: 16);
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ArenaGlassCard(
              tint: StudioPalette.gold,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: _pages.length < 2
                        ? null
                        : () => setState(() {
                              _pages.removeLast();
                              _pageFuture = null;
                              _expandedQuestionIds.clear();
                            }),
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    label: const Text('Önceki', style: TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: StudioPalette.gold.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.55)),
                            ),
                            child: Text(
                              'Sayfa ${_pages.length}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                color: StudioPalette.goldBright,
                              ),
                            ),
                          ),
                        ),
                        if (_pages.length > 2) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'İlk sayfaya dön',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () => setState(() {
                              _pages
                                ..clear()
                                ..add(firstBrowserPage);
                              _pageFuture = null;
                              _expandedQuestionIds.clear();
                            }),
                            icon: const Icon(Icons.first_page_rounded,
                                size: 18, color: StudioPalette.goldBright),
                          ),
                        ],
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: page?.hasMore != true
                        ? null
                        : () => setState(() {
                              _pages.add(page!.next);
                              _pageFuture = null;
                              _expandedQuestionIds.clear();
                            }),
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    label: const Text('Sonraki', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          );
        }

        final q = shown[index - 1];
        return _buildPoolQuestionCard(context, ctrl, q, accent);
      },
    );
  }

  Widget _buildPoolQuestionCard(
    BuildContext context,
    ArenaController ctrl,
    Question q,
    Color accent,
  ) {
    final expanded = _expandedQuestionIds.contains(q.id);
    final bookmarked = ctrl.isBookmarked(q);
    final reported = ctrl.isReported(q);
    final solved = ctrl.playedQuestionIds.contains(q.id);
    final inReview = ctrl.isInReviewDeck(q);
    final selectedOpt = _selfTestSelections[q.id];
    final answerShown = _revealedAnswers.contains(q.id) || selectedOpt != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ArenaGlassCard(
        tint: q.category.accent,
        padding: const EdgeInsets.all(13),
        onTap: () => setState(() {
          if (expanded) {
            _expandedQuestionIds.remove(q.id);
          } else {
            _expandedQuestionIds.add(q.id);
          }
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.asset(
                          q.category.detailImage,
                          width: 36,
                          height: 28,
                          cacheWidth: 120,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: q.category.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: q.category.accent.withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          q.category.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: q.category.accent,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: q.difficulty.color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          q.difficulty.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: q.difficulty.color,
                          ),
                        ),
                      ),
                      if (q.bloom != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: StudioPalette.navyTop.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            q.bloom!.label,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: StudioPalette.goldBright,
                            ),
                          ),
                        ),
                      if (solved)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: StudioPalette.emerald.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            '✓ Çözüldü',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF7AF0A8),
                            ),
                          ),
                        ),
                      if (inReview)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC5A3FF).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            '↻ Tekrarda',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFD6BEFF),
                            ),
                          ),
                        ),
                      if (q.visual != null)
                        Icon(Icons.bar_chart_rounded, size: 15, color: accent),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => ctrl.toggleBookmark(q),
                  borderRadius: BorderRadius.circular(99),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      size: 20,
                      color: bookmarked ? StudioPalette.goldBright : Colors.white60,
                    ),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: Colors.white54,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              q.text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.32,
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 10),
              if (q.creation != null) ...[
                Text(
                  q.creation!.brief,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                for (final criterion in q.creation!.criteria)
                  Text('• $criterion', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 8),
              ],
              if (q.visual != null) ...[
                QuestionVisualViewer(visual: q.visual!, accent: q.category.accent),
                const SizedBox(height: 8),
              ],
              // Kart içi etkileşimli kendini sına şıkları!
              if (q.options.isNotEmpty) ...[
                Text(
                  selectedOpt == null
                      ? 'Kendini Sına (Bir şık seç veya cevabı aç):'
                      : (selectedOpt == q.answer ? 'Harika! Doğru yanıtladın.' : 'Yanlış şık — doğru yanıt vurgulandı.'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selectedOpt == null
                        ? StudioPalette.goldBright
                        : (selectedOpt == q.answer
                            ? const Color(0xFF7AF0A8)
                            : const Color(0xFFFF8F9B)),
                  ),
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < q.options.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: _inlineOptionTile(
                      letter: String.fromCharCode(65 + i),
                      text: q.options[i],
                      isCorrect: i == q.answer,
                      isSelected: selectedOpt == i,
                      revealed: answerShown,
                      onTap: () => setState(() {
                        _selfTestSelections[q.id] = i;
                        _revealedAnswers.add(q.id);
                      }),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 6),
              if (!answerShown)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _revealedAnswers.add(q.id)),
                    icon: const Icon(Icons.visibility_rounded, size: 16),
                    label: const Text('Doğru Yanıtı & Açıklamayı Göster'),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: StudioPalette.emerald.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: StudioPalette.emerald.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Doğru Yanıt: ${q.correctAnswerText}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF7AF0A8),
                        ),
                      ),
                      if (q.explanation.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          q.explanation,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.88),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _cardMiniAction(
                    icon: Icons.play_arrow_rounded,
                    label: 'Soruyu Çöz',
                    color: StudioPalette.goldBright,
                    onTap: () => ctrl.startQuestionPractice(q),
                  ),
                  _cardMiniAction(
                    icon: inReview ? Icons.check_circle_rounded : Icons.replay_rounded,
                    label: inReview ? 'Tekrar Destesinde' : 'Tekrara Ekle',
                    color: const Color(0xFFC5A3FF),
                    onTap: () {
                      ctrl.addQuestionToReviewDeck(q);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Soru Leitner tekrar destesine eklendi.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  _cardMiniAction(
                    icon: reported ? Icons.visibility_rounded : Icons.flag_outlined,
                    label: reported ? 'Geri Aç' : 'Gizle',
                    color: Colors.white70,
                    onTap: () => ctrl.toggleReportQuestion(q),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _inlineOptionTile({
    required String letter,
    required String text,
    required bool isCorrect,
    required bool isSelected,
    required bool revealed,
    required VoidCallback onTap,
  }) {
    Color borderColor = StudioPalette.gold.withValues(alpha: 0.28);
    Color bgColor = StudioPalette.navyDark.withValues(alpha: 0.72);
    Color letterBg = StudioPalette.gold.withValues(alpha: 0.16);
    Color letterFg = StudioPalette.goldBright;

    if (revealed && isCorrect) {
      borderColor = StudioPalette.emerald;
      bgColor = StudioPalette.emerald.withValues(alpha: 0.18);
      letterBg = StudioPalette.emerald;
      letterFg = Colors.white;
    } else if (revealed && isSelected && !isCorrect) {
      borderColor = StudioPalette.crimson;
      bgColor = StudioPalette.crimson.withValues(alpha: 0.2);
      letterBg = StudioPalette.crimson;
      letterFg = Colors.white;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: bgColor,
          border: Border.all(color: borderColor, width: revealed && (isCorrect || isSelected) ? 1.5 : 1.0),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: letterBg,
              ),
              child: Text(
                letter,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: letterFg),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            if (revealed && isCorrect)
              const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF7AF0A8))
            else if (revealed && isSelected && !isCorrect)
              const Icon(Icons.cancel_rounded, size: 16, color: Color(0xFFFF8F9B)),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // BÖLÜM 1: TEKRAR (LEITNER 6-KUTU ARALIKLI TEKRAR STÜDYOSU)
  // =========================================================================
  Widget _buildSpacedRepetitionView(BuildContext context, ArenaController ctrl, Color accent) {
    final now = DateTime.now();
    final deck = ctrl.reviewDeck;
    final dueCards = ctrl.dueReviewCards;
    final boxCounts = List<int>.filled(6, 0);
    var totalAttempts = 0;
    var totalCorrect = 0;
    for (final c in deck) {
      boxCounts[c.box.clamp(0, 5)]++;
      totalAttempts += c.attempts;
      totalCorrect += c.correct;
    }
    final avgAcc = totalAttempts == 0 ? 0 : ((totalCorrect / totalAttempts) * 100).round();
    final masteredCount = boxCounts[4] + boxCounts[5];
    final maxBoxCount = boxCounts.fold<int>(1, max);

    final deckTopics = deck.map((c) => c.question.category).toSet().toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final filtered = deck.where((c) {
      if (_reviewOnlyDue && c.due.isAfter(now)) return false;
      if (_reviewBoxFilter != null && c.box != _reviewBoxFilter) return false;
      if (_reviewTopicFilter != null && c.question.category != _reviewTopicFilter) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    const boxLabels = ['5dk', '1g', '3g', '7g', '14g', '30g'];
    const boxColors = [
      StudioPalette.crimson,
      StudioPalette.amber,
      StudioPalette.gold,
      Color(0xFF8BE27B),
      StudioPalette.emerald,
      StudioPalette.sapphire,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 108),
      children: [
        // Hero Leitner Durum Plaketi
        Studio3DPlaque(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          chamfer: 15,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: StudioPalette.gold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.7)),
                    ),
                    child: const Icon(Icons.psychology_alt_rounded,
                        color: StudioPalette.goldBright, size: 22),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dueCards.isEmpty
                              ? 'Tekrar Zamanı Temiz'
                              : '${dueCards.length} Soru Tekrar Zamanında!',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: StudioPalette.goldBright,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${deck.length} kart · %$avgAcc tekrar başarısı · $masteredCount uzmanlaşmış',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: Studio3DButton(
                      label: 'Tekrar Turu',
                      icon: Icons.play_arrow_rounded,
                      expand: true,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      onPressed: filtered.isEmpty
                          ? null
                          : () => ctrl.startReviewRound(
                                boxFilter: _reviewBoxFilter,
                                topicFilter: _reviewTopicFilter,
                                onlyDue: _reviewOnlyDue,
                              ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Studio3DButton(
                      label: '3D Kartla Çalış',
                      icon: Icons.flip_rounded,
                      variant: StudioButtonVariant.emerald,
                      shimmer: false,
                      expand: true,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      onPressed: filtered.isEmpty
                          ? null
                          : () => _openFlashcardStudy(
                                context,
                                questions: filtered.map((c) => c.question).toList(),
                                title: 'Leitner 3D Tekrar Kartları',
                                leitnerMode: true,
                              ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 6-Kutu Leitner Görsel Dağılım Panosu (Tıklayarak kutu filtrele!)
        ArenaGlassCard(
          tint: StudioPalette.gold,
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Leitner 6 Kutu Dağılımı (Filtrelemek için dokun)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: StudioPalette.goldBright,
                      ),
                    ),
                  ),
                  if (_reviewBoxFilter != null)
                    InkWell(
                      onTap: () => setState(() => _reviewBoxFilter = null),
                      child: const Text(
                        'Tümü',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: StudioPalette.gold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 92,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var b = 0; b < 6; b++) ...[
                      if (b > 0) const SizedBox(width: 6),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() {
                            _reviewBoxFilter = _reviewBoxFilter == b ? null : b;
                          }),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: _reviewBoxFilter == b
                                  ? boxColors[b].withValues(alpha: 0.24)
                                  : Colors.white.withValues(alpha: 0.04),
                              border: Border.all(
                                color: _reviewBoxFilter == b
                                    ? boxColors[b]
                                    : Colors.white.withValues(alpha: 0.1),
                                width: _reviewBoxFilter == b ? 1.6 : 1.0,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '${boxCounts[b]}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    color: boxCounts[b] > 0 ? boxColors[b] : Colors.white38,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: boxCounts[b] == 0
                                          ? 0.12
                                          : (0.2 + 0.8 * (boxCounts[b] / maxBoxCount)).clamp(0.2, 1.0),
                                      widthFactor: 0.65,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(6),
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              boxColors[b],
                                              boxColors[b].withValues(alpha: 0.35),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'K${b + 1}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  boxLabels[b],
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Durum & Konu Filtreleri
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _colorFilterPill(
                label: 'Tümü (${deck.length})',
                selected: !_reviewOnlyDue && _reviewTopicFilter == null,
                color: StudioPalette.gold,
                onTap: () => setState(() {
                  _reviewOnlyDue = false;
                  _reviewTopicFilter = null;
                }),
              ),
              const SizedBox(width: 6),
              _colorFilterPill(
                label: 'Zamanı Gelenler (${dueCards.length})',
                selected: _reviewOnlyDue,
                color: StudioPalette.amber,
                onTap: () => setState(() => _reviewOnlyDue = !_reviewOnlyDue),
              ),
              for (final t in deckTopics) ...[
                const SizedBox(width: 6),
                _colorFilterPill(
                  label: t.label,
                  selected: _reviewTopicFilter == t,
                  color: t.accent,
                  onTap: () => setState(() {
                    _reviewTopicFilter = _reviewTopicFilter == t ? null : t;
                  }),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (deck.isEmpty)
          _emptyBox(
            'Tekrar Defterin Tertemiz',
            'Bir tur oynadığında zorlandığın sorular otomatik olarak buraya eklenir. Havuzdan da dilediğin soruyu "Tekrara Ekle" ile ekleyebilirsin.',
            Icons.auto_stories_rounded,
            accent,
          )
        else if (filtered.isEmpty)
          _emptyBox(
            'Bu Filtrede Tekrar Kartı Yok',
            'Başka bir Leitner kutusu veya kategori seçerek tüm kartlarını görebilirsin.',
            Icons.filter_alt_off_rounded,
            accent,
          ),

        for (final card in filtered) _buildReviewCardTile(context, ctrl, card, now, boxColors),
      ],
    );
  }

  Widget _buildReviewCardTile(
    BuildContext context,
    ArenaController ctrl,
    ReviewCard card,
    DateTime now,
    List<Color> boxColors,
  ) {
    final isDue = !card.due.isAfter(now);
    final boxIdx = card.box.clamp(0, 5);
    final boxColor = boxColors[boxIdx];
    final expanded = _expandedReviewIds.contains(card.question.id);
    final acc = card.attempts == 0 ? 0 : ((card.correct / card.attempts) * 100).round();

    String dueText;
    if (isDue) {
      dueText = 'Şimdi Tekrar Et!';
    } else {
      final diff = card.due.difference(now);
      if (diff.inDays >= 1) {
        dueText = '${diff.inDays} gün sonra';
      } else if (diff.inHours >= 1) {
        dueText = '${diff.inHours} sa ${diff.inMinutes % 60} dk';
      } else {
        dueText = '${max(1, diff.inMinutes)} dk sonra';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: ArenaGlassCard(
        tint: isDue ? StudioPalette.amber : boxColor,
        padding: const EdgeInsets.all(13),
        onTap: () => setState(() {
          if (expanded) {
            _expandedReviewIds.remove(card.question.id);
          } else {
            _expandedReviewIds.add(card.question.id);
          }
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: boxColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: boxColor.withValues(alpha: 0.7)),
                  ),
                  child: Text(
                    'Kutu ${boxIdx + 1}/6',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: boxColor),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    card.question.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: card.question.category.accent,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDue
                        ? StudioPalette.amber.withValues(alpha: 0.24)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: isDue ? StudioPalette.amber : Colors.white24,
                    ),
                  ),
                  child: Text(
                    dueText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isDue ? StudioPalette.goldBright : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            // 6 noktalı Leitner ustalık göstergesi + başarı yüzdesi
            Row(
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Container(
                    width: 14,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: i <= boxIdx ? boxColor : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${card.attempts} deneme · ${card.correct} doğru (%$acc)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 10.5, color: Colors.white60),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              card.question.text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.3,
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: StudioPalette.emerald.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: StudioPalette.emerald.withValues(alpha: 0.42)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Doğru Yanıt: ${card.question.correctAnswerText}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF7AF0A8),
                      ),
                    ),
                    if (card.question.explanation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        card.question.explanation,
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _cardMiniAction(
                    icon: Icons.play_arrow_rounded,
                    label: 'Şimdi Çöz',
                    color: StudioPalette.goldBright,
                    onTap: () => ctrl.startQuestionPractice(card.question),
                  ),
                  _cardMiniAction(
                    icon: Icons.flip_rounded,
                    label: '3D Kart',
                    color: StudioPalette.emerald,
                    onTap: () => _openFlashcardStudy(
                      context,
                      questions: [card.question],
                      title: 'Tekil Leitner Kartı',
                      leitnerMode: true,
                    ),
                  ),
                  _cardMiniAction(
                    icon: Icons.delete_outline_rounded,
                    label: 'Desteden Çıkar',
                    color: StudioPalette.crimson,
                    onTap: () => ctrl.removeReviewCard(card.question.id),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // BÖLÜM 2: DEFTERİM (KİŞİSEL BİLGİ DEFTERİ)
  // =========================================================================
  Widget _buildBookmarksView(BuildContext context, ArenaController ctrl, Color accent) {
    final all = ctrl.savedBookmarks;
    final topics = all.map((q) => q.category).toSet().toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final qLower = _bookmarkQuery.trim().toLowerCase();
    final filtered = all.where((q) {
      if (_bookmarkTopicFilter != null && q.category != _bookmarkTopicFilter) return false;
      if (qLower.isNotEmpty) {
        return q.text.toLowerCase().contains(qLower) ||
            q.explanation.toLowerCase().contains(qLower) ||
            q.correctAnswerText.toLowerCase().contains(qLower);
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 108),
      children: [
        if (all.isNotEmpty) ...[
          ArenaGlassCard(
            tint: StudioPalette.gold,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_stories_rounded, color: StudioPalette.goldBright, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${all.length} Kayıtlı Soru · ${topics.length} Farklı Alan',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: StudioPalette.goldBright,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Studio3DButton(
                        label: 'Defterden Test',
                        icon: Icons.play_arrow_rounded,
                        expand: true,
                        fontSize: 13,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        onPressed: filtered.isEmpty
                            ? null
                            : () => ctrl.startBookmarksRound(topicFilter: _bookmarkTopicFilter),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Studio3DButton(
                        label: '3D Kart Modu',
                        icon: Icons.style_rounded,
                        variant: StudioButtonVariant.navy,
                        shimmer: false,
                        expand: true,
                        fontSize: 13,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        onPressed: filtered.isEmpty
                            ? null
                            : () => _openFlashcardStudy(
                                  context,
                                  questions: filtered,
                                  title: 'Bilgi Defterim 3D Kartlar',
                                  leitnerMode: false,
                                ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bookmarkSearchCtrl,
            onChanged: (v) => setState(() => _bookmarkQuery = v),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Kayıtlı sorularında ara...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 12.5),
              prefixIcon: const Icon(Icons.search_rounded, color: StudioPalette.gold, size: 19),
              suffixIcon: _bookmarkQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                      onPressed: () => setState(() {
                        _bookmarkQuery = '';
                        _bookmarkSearchCtrl.clear();
                      }),
                    )
                  : null,
              filled: true,
              fillColor: StudioPalette.navyTop.withValues(alpha: 0.58),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: StudioPalette.gold.withValues(alpha: 0.32)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: StudioPalette.gold, width: 1.5),
              ),
            ),
          ),
          if (topics.length > 1) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _colorFilterPill(
                    label: 'Tümü (${all.length})',
                    selected: _bookmarkTopicFilter == null,
                    color: StudioPalette.gold,
                    onTap: () => setState(() => _bookmarkTopicFilter = null),
                  ),
                  for (final t in topics) ...[
                    const SizedBox(width: 6),
                    _colorFilterPill(
                      label: t.label,
                      selected: _bookmarkTopicFilter == t,
                      color: t.accent,
                      onTap: () => setState(() {
                        _bookmarkTopicFilter = _bookmarkTopicFilter == t ? null : t;
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],

        if (all.isEmpty)
          _emptyBox(
            'Bilgi Defterin Hazır',
            'Oyun sırasında veya Havuz sekmesinde yer işareti simgesine dokunarak favori sorularını burada topla ve kendi özel testlerini oluştur.',
            Icons.bookmark_added_rounded,
            accent,
          )
        else if (filtered.isEmpty)
          _emptyBox(
            'Eşleşen Kayıt Bulunamadı',
            'Arama sözcüğünü veya kategori filtresini değiştir.',
            Icons.search_off_rounded,
            accent,
          ),

        for (final q in filtered) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ArenaGlassCard(
              tint: q.category.accent,
              padding: const EdgeInsets.all(13),
              onTap: () => setState(() {
                if (!_expandedBookmarkIds.remove(q.id)) {
                  _expandedBookmarkIds.add(q.id);
                }
              }),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          q.category.detailImage,
                          width: 34,
                          height: 26,
                          cacheWidth: 100,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${q.category.label.toUpperCase()} · ${q.difficulty.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: q.category.accent,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ctrl.toggleBookmark(q),
                        icon: const Icon(
                          Icons.bookmark_remove_rounded,
                          color: StudioPalette.goldBright,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    q.text,
                    style: const TextStyle(
                      fontSize: 13.8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: StudioPalette.emerald.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: StudioPalette.emerald.withValues(alpha: 0.36)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Yanıt: ${q.correctAnswerText}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF7AF0A8),
                          ),
                        ),
                        if (q.explanation.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            q.explanation,
                            maxLines: _expandedBookmarkIds.contains(q.id) ? null : 3,
                            overflow: _expandedBookmarkIds.contains(q.id)
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.84),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _cardMiniAction(
                        icon: Icons.play_arrow_rounded,
                        label: 'Bu Soruyu Çöz',
                        color: StudioPalette.goldBright,
                        onTap: () => ctrl.startQuestionPractice(q),
                      ),
                      _cardMiniAction(
                        icon: Icons.replay_rounded,
                        label: ctrl.isInReviewDeck(q) ? 'Tekrarda ✓' : 'Tekrara Ekle',
                        color: const Color(0xFFC5A3FF),
                        onTap: () => ctrl.addQuestionToReviewDeck(q),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // =========================================================================
  // BÖLÜM 3: PAKETLER (ÇEVRİMDIŞI PAKET MERKEZİ)
  // =========================================================================
  _PackGroup _classifyPack(QuestionPack pack) {
    if (!pack.id.startsWith('builtin_sb_')) return _PackGroup.personal;
    if (pack.id.contains('_topic_')) return _PackGroup.topic;
    if (pack.id.contains('_bloom_')) return _PackGroup.bloom;
    return _PackGroup.general;
  }

  Widget _buildPacksView(BuildContext context, ArenaController ctrl, Color accent) {
    final qLower = _packQuery.trim().toLowerCase();
    final filtered = ctrl.offlinePacks.where((p) {
      if (_packGroup != _PackGroup.all && _classifyPack(p) != _packGroup) return false;
      if (qLower.isNotEmpty && !p.title.toLowerCase().contains(qLower)) return false;
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 108),
      children: [
        ArenaGlassCard(
          tint: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.folder_zip_rounded, color: StudioPalette.goldBright, size: 19),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Soru Paketi Aktarımı (JSON)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: StudioPalette.goldBright,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Kişisel soru paketlerini JSON olarak içe veya dışa aktarabilirsin. Yerleşik 23 konu ve Bloom paketleri tamamen çevrimdışı hazırdır.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.74)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Studio3DButton(
                      label: 'JSON İçe Aktar',
                      icon: Icons.file_open_rounded,
                      expand: true,
                      fontSize: 13.5,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      onPressed: () async {
                        final msg = await ctrl.importJsonQuestionPacks();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        }
                      },
                    ),
                  ),
                  if (ctrl.lastImportedPackId != null) ...[
                    const SizedBox(width: 8),
                    Studio3DButton(
                      label: 'Geri Al',
                      icon: Icons.undo_rounded,
                      variant: StudioButtonVariant.navy,
                      shimmer: false,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      onPressed: () {
                        ctrl.undoLastImport();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Son içe aktarım geri alındı.')),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Paket arama + grup filtresi + tur uzunluğu seçici
        TextField(
          controller: _packSearchCtrl,
          onChanged: (v) => setState(() => _packQuery = v),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Paket ara (Matematik, Bloom, Özgün...)',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 12.5),
            prefixIcon: const Icon(Icons.search_rounded, color: StudioPalette.gold, size: 19),
            suffixIcon: _packQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                    onPressed: () => setState(() {
                      _packQuery = '';
                      _packSearchCtrl.clear();
                    }),
                  )
                : null,
            filled: true,
            fillColor: StudioPalette.navyTop.withValues(alpha: 0.58),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: StudioPalette.gold.withValues(alpha: 0.32)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: StudioPalette.gold, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ArenaScrollPills<_PackGroup>(
          items: _PackGroup.values,
          selected: _packGroup,
          labelBuilder: (g) => g.label,
          onSelected: (g) => setState(() => _packGroup = g),
          accent: accent,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'Paket Tur Uzunluğu:',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white70),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ArenaScrollPills<int>(
                items: const [10, 15, 20, 30],
                selected: _packPlayCount,
                labelBuilder: (n) => '$n Soru',
                onSelected: (n) => setState(() => _packPlayCount = n),
                accent: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (filtered.isEmpty)
          _emptyBox(
            'Çevrimdışı Paket Arşivin',
            'Seçtiğin filtrede paket bulunamadı. JSON ile kendi paketini içe aktarabilir veya tüm gruplara dönebilirsin.',
            Icons.inventory_2_rounded,
            accent,
          ),

        for (final pack in filtered) _buildPackCard(context, ctrl, pack, accent),
      ],
    );
  }

  Widget _buildPackCard(
    BuildContext context,
    ArenaController ctrl,
    QuestionPack pack,
    Color accent,
  ) {
    final group = _classifyPack(pack);
    final isPersonal = group == _PackGroup.personal;
    final icon = switch (group) {
      _PackGroup.personal => Icons.file_present_rounded,
      _PackGroup.topic => Icons.category_rounded,
      _PackGroup.bloom => Icons.psychology_rounded,
      _ => Icons.library_books_rounded,
    };
    final tint = switch (group) {
      _PackGroup.personal => StudioPalette.emerald,
      _PackGroup.bloom => const Color(0xFFC5A3FF),
      _PackGroup.topic => StudioPalette.sapphire,
      _ => StudioPalette.gold,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ArenaGlassCard(
        tint: tint,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: tint.withValues(alpha: 0.5)),
                  ),
                  child: Icon(icon, size: 18, color: tint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pack.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatNum(pack.questions.length)} soru · ${group.label} · Çevrimdışı',
                        style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.68)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: Studio3DButton(
                    label: 'Oyna ($_packPlayCount)',
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    fontSize: 13,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    onPressed: () => ctrl.startPackRound(pack, maxQuestions: _packPlayCount),
                  ),
                ),
                if (pack.questions is! FamilyQuestions) ...[
                  const SizedBox(width: 8),
                  Studio3DButton(
                    label: 'JSON',
                    icon: Icons.download_rounded,
                    variant: StudioButtonVariant.navy,
                    shimmer: false,
                    fontSize: 12.5,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    onPressed: () => ctrl.exportQuestionPack(pack),
                  ),
                ],
                if (isPersonal) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Paketi Sil',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ctrl.deleteOfflinePack(pack.id),
                    icon: const Icon(Icons.delete_outline_rounded, color: StudioPalette.crimson),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // BÖLÜM 4: PROFİLLER (SINAV ÇALIŞMA PROFİLLERİ)
  // =========================================================================
  Widget _buildProfilesView(BuildContext context, ArenaController ctrl, Color accent) {
    final quickTemplates = const [
      (ExamKind.tyt, 'Türkçe', Difficulty.medium, 15, 'TYT Türkçe Hız'),
      (ExamKind.ayt, 'Fizik', Difficulty.hard, 10, 'AYT Fizik Kampı'),
      (ExamKind.kpss, 'Coğrafya', Difficulty.medium, 15, 'KPSS Coğrafya'),
      (ExamKind.lgs, 'Matematik', Difficulty.easy, 10, 'LGS Matematik'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 108),
      children: [
        Studio3DButton(
          label: 'Yeni TYT / AYT / KPSS / LGS Profili Ekle',
          icon: Icons.add_rounded,
          expand: true,
          fontSize: 13.5,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onPressed: () => _showProfileSheet(context),
        ),
        const SizedBox(height: 12),

        // Tek Dokunuşla Hazır Sınav Şablonları
        const Studio3DSectionHeader(
          icon: Icons.bolt_rounded,
          title: 'Hızlı Şablonlar',
          badge: 'Tek Dokunuş',
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final tpl in quickTemplates) ...[
                ArenaPressDepth(
                  depthOffset: 1.5,
                  child: InkWell(
                    onTap: () {
                      ctrl.addStudyProfile(
                        StudyProfile(
                          id: 'prof_${DateTime.now().microsecondsSinceEpoch}',
                          title: tpl.$5,
                          exam: tpl.$1,
                          lesson: tpl.$2,
                          difficulty: tpl.$3,
                          questionCount: tpl.$4,
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${tpl.$5} profili eklendi.')),
                      );
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [StudioPalette.navyTop, StudioPalette.navyDark],
                        ),
                        border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_circle_outline_rounded,
                              size: 15, color: StudioPalette.goldBright),
                          const SizedBox(width: 6),
                          Text(
                            tpl.$5,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        Studio3DSectionHeader(
          icon: Icons.school_rounded,
          title: 'Kayıtlı Çalışma Profillerim',
          badge: '${ctrl.studyProfiles.length}',
        ),
        const SizedBox(height: 10),

        for (final p in ctrl.studyProfiles) _buildProfileCard(context, ctrl, p),
      ],
    );
  }

  Widget _buildProfileCard(BuildContext context, ArenaController ctrl, StudyProfile p) {
    final examColor = switch (p.exam) {
      ExamKind.tyt => StudioPalette.gold,
      ExamKind.ayt => StudioPalette.sapphire,
      ExamKind.kpss => StudioPalette.emerald,
      ExamKind.lgs => const Color(0xFFFF9559),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ArenaGlassCard(
        tint: examColor,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: examColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: examColor.withValues(alpha: 0.7)),
                  ),
                  child: Text(
                    p.exam.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: examColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${p.lesson} · ${p.difficulty.label} · ${p.questionCount} Soru',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: Studio3DButton(
                    label: 'Başlat',
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    fontSize: 13,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    onPressed: () {
                      if (!ctrl.startStudyProfileRound(p)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Bu çalışma profilindeki ders ve zorlukta soru bulunamadı.'),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Düzenle',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showProfileSheet(context, editing: p),
                  icon: const Icon(Icons.edit_outlined, color: StudioPalette.goldBright, size: 20),
                ),
                IconButton(
                  tooltip: 'Sil',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ctrl.deleteStudyProfile(p.id),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // ORTAK YARDIMCI BİLEŞENLER
  // =========================================================================
  bool _setEquals(Set<Topic> a, Set<Topic> b) => a.length == b.length && a.containsAll(b);

  Widget _tappableMiniStat({
    required String label,
    required String value,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: active ? color.withValues(alpha: 0.16) : Colors.transparent,
          border: active ? Border.all(color: color.withValues(alpha: 0.55)) : null,
        ),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: color),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.72)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorFilterPill({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ArenaPressDepth(
      depthOffset: 1.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: selected
                ? LinearGradient(colors: [Color.lerp(color, Colors.white, 0.25)!, color])
                : const LinearGradient(colors: [Color(0xE01A2A88), Color(0xE0081044)]),
            border: Border.all(
              color: selected ? Colors.white : color.withValues(alpha: 0.45),
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              color: selected ? StudioPalette.night : Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bundleQuickChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: active ? StudioPalette.gold.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: active ? StudioPalette.goldBright : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w900 : FontWeight.w700,
            color: active ? StudioPalette.goldBright : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _multiTopicChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ArenaPressDepth(
      depthOffset: 1.8,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      StudioPalette.gold.withValues(alpha: 0.34),
                      StudioPalette.navyTop.withValues(alpha: 0.92),
                    ],
                  )
                : LinearGradient(
                    colors: [
                      StudioPalette.navyMid.withValues(alpha: 0.72),
                      StudioPalette.navyDark.withValues(alpha: 0.85),
                    ],
                  ),
            border: Border.all(
              color: selected ? StudioPalette.gold : color.withValues(alpha: 0.34),
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_circle_rounded, size: 13, color: StudioPalette.goldBright),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.8,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? StudioPalette.goldBright : Colors.white.withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardMiniAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: color.withValues(alpha: 0.14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: 11.2, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBox(String title, String subtitle, IconData icon, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: accent.withValues(alpha: 0.14),
            child: Icon(icon, size: 30, color: accent),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.68)),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 3D ÇEVRİLEN ETKİLEŞİMLİ KART ÇALIŞMA MODALI (FLASHCARD STUDIO)
// ===========================================================================
class _Studio3DFlashcardSheet extends StatefulWidget {
  final ArenaController controller;
  final List<Question> questions;
  final String title;
  final bool leitnerMode;

  const _Studio3DFlashcardSheet({
    required this.controller,
    required this.questions,
    required this.title,
    required this.leitnerMode,
  });

  @override
  State<_Studio3DFlashcardSheet> createState() => _Studio3DFlashcardSheetState();
}

class _Studio3DFlashcardSheetState extends State<_Studio3DFlashcardSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipCtrl;
  int _index = 0;
  bool _flipped = false;
  int _rememberedCount = 0;
  int _hardCount = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    setState(() => _flipped = !_flipped);
    if (_flipped) {
      _flipCtrl.forward();
    } else {
      _flipCtrl.reverse();
    }
  }

  void _advance({bool? remembered}) {
    final q = widget.questions[_index];
    if (widget.leitnerMode && remembered != null) {
      widget.controller.recordFlashcardReview(q, remembered);
      if (remembered) {
        _rememberedCount++;
      } else {
        _hardCount++;
      }
    }
    if (_index + 1 >= widget.questions.length) {
      setState(() => _completed = true);
      return;
    }
    setState(() {
      _index++;
      _flipped = false;
      _flipCtrl.value = 0;
    });
  }

  void _goBack() {
    if (_index == 0) return;
    setState(() {
      _index--;
      _flipped = false;
      _flipCtrl.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [StudioPalette.navyMid, StudioPalette.night],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: StudioPalette.gold, width: 1.8)),
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        14,
        18,
        MediaQuery.of(context).padding.bottom + 18,
      ),
      child: _completed ? _buildSummary(context) : _buildCardStage(context, ctrl),
    );
  }

  Widget _buildSummary(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Studio3DOrbitEmblem(icon: Icons.emoji_events_rounded, size: 68),
        const SizedBox(height: 12),
        const Text(
          'Kart Oturumu Tamamlandı!',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: StudioPalette.goldBright,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.leitnerMode
              ? '$_rememberedCount hatırlanan (+${_rememberedCount * 5} XP) · $_hardCount tekrar kutusuna alındı'
              : '${widget.questions.length} bilgi kartı gözden geçirildi.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        const SizedBox(height: 18),
        Studio3DButton(
          label: 'Akademiye Dön',
          icon: Icons.check_rounded,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildCardStage(BuildContext context, ArenaController ctrl) {
    final q = widget.questions[_index];
    final bookmarked = ctrl.isBookmarked(q);
    final ratio = (_index + 1) / widget.questions.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Üst tutamak + başlık
        Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: StudioPalette.gold.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: StudioPalette.goldBright,
                ),
              ),
            ),
            Text(
              '${_index + 1} / ${widget.questions.length}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => ctrl.toggleBookmark(q)),
              icon: Icon(
                bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                color: bookmarked ? StudioPalette.goldBright : Colors.white60,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Studio3DProgressBar(value: ratio, height: 6),
        const SizedBox(height: 14),

        // 3D Çevrilebilir Kart
        GestureDetector(
          onTap: _toggleFlip,
          child: AnimatedBuilder(
            animation: _flipCtrl,
            builder: (context, _) {
              final angle = _flipCtrl.value * pi;
              final showBack = angle > pi / 2;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0014)
                  ..rotateY(angle),
                child: showBack
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(pi),
                        child: _buildBackFace(q),
                      )
                    : _buildFrontFace(q),
              );
            },
          ),
        ),
        const SizedBox(height: 14),

        // Alt Kontroller
        if (!_flipped)
          Studio3DButton(
            label: 'Kartı Çevir ve Cevabı Gör',
            icon: Icons.flip_rounded,
            expand: true,
            onPressed: _toggleFlip,
          )
        else if (widget.leitnerMode)
          Row(
            children: [
              Expanded(
                child: Studio3DButton(
                  label: 'Zorlandım (K1)',
                  icon: Icons.refresh_rounded,
                  variant: StudioButtonVariant.crimson,
                  shimmer: false,
                  expand: true,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                  onPressed: () => _advance(remembered: false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Studio3DButton(
                  label: 'Hatırladım (+5 XP)',
                  icon: Icons.check_circle_rounded,
                  variant: StudioButtonVariant.emerald,
                  expand: true,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                  onPressed: () => _advance(remembered: true),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Studio3DButton(
                label: 'Önceki',
                icon: Icons.chevron_left_rounded,
                variant: StudioButtonVariant.navy,
                shimmer: false,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                onPressed: _index == 0 ? null : _goBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Studio3DButton(
                  label: _index + 1 >= widget.questions.length ? 'Bitir' : 'Sonraki Kart',
                  icon: Icons.chevron_right_rounded,
                  expand: true,
                  fontSize: 13.5,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  onPressed: () => _advance(),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildFrontFace(Question q) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 230, maxHeight: 340),
      child: ArenaGlassCard(
        tint: q.category.accent,
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: q.category.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${q.category.label} · ${q.difficulty.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: q.category.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'ÖN YÜZ · DOKUN',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: StudioPalette.goldBright,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                q.text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.35,
                ),
              ),
              if (q.options.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (var i = 0; i < q.options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${String.fromCharCode(65 + i)}) ${q.options[i]}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackFace(Question q) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 230, maxHeight: 340),
      child: ArenaGlassCard(
        tint: StudioPalette.emerald,
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_rounded, color: Color(0xFF7AF0A8), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'DOĞRU YANIT & ÇÖZÜM',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Color(0xFF7AF0A8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                q.correctAnswerText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: StudioPalette.goldBright,
                  height: 1.25,
                ),
              ),
              if (q.explanation.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  q.explanation,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
