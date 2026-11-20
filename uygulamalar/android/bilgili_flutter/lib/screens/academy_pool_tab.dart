import 'package:flutter/material.dart';
import '../models/quiz_models.dart';
import '../state/arena_controller.dart';
import '../theme/arena_design.dart';
import '../widgets/question_renderers.dart';

class AcademyPoolTab extends StatefulWidget {
  final ArenaController controller;
  const AcademyPoolTab({super.key, required this.controller});

  @override
  State<AcademyPoolTab> createState() => _AcademyPoolTabState();
}

class _AcademyPoolTabState extends State<AcademyPoolTab> {
  int _section = 0; // 0: Havuz, 1: Tekrar, 2: Defterim, 3: Paketler, 4: Profiller
  String _query = '';
  Topic _filterTopic = Topic.mixed;
  QuestionFormat _filterFormat = QuestionFormat.mixed;
  bool _hideReported = true;
  int _visibleLimit = 30;
  final Set<String> _expandedQuestionIds = {};

  void _showCreateProfileSheet(BuildContext context) {
    ExamKind exam = ExamKind.tyt;
    String lesson = ExamKind.tyt.lessons.first;
    Difficulty diff = Difficulty.medium;
    int count = 10;
    final titleCtrl = TextEditingController(text: 'TYT Odak Çalışması');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1324),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Yeni Sınav Çalışma Profili',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Profil Adı',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
                ArenaScrollPills<String>(
                  items: exam.lessons,
                  selected: lesson,
                  labelBuilder: (l) => l,
                  onSelected: (l) => setSheet(() => lesson = l),
                  accent: accent,
                ),
                const SizedBox(height: 10),
                ArenaScrollPills<Difficulty>(
                  items: Difficulty.values,
                  selected: diff,
                  labelBuilder: (d) => d.label,
                  onSelected: (d) => setSheet(() => diff = d),
                  accent: accent,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    widget.controller.addStudyProfile(
                      StudyProfile(
                        id: 'prof_${DateTime.now().millisecondsSinceEpoch}',
                        title: titleCtrl.text.trim().isEmpty
                            ? '${exam.label} · $lesson'
                            : titleCtrl.text.trim(),
                        exam: exam,
                        lesson: lesson,
                        difficulty: diff,
                        questionCount: count,
                      ),
                    );
                    Navigator.of(ctx).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: const Color(0xFF06101F),
                  ),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Profili Kaydet'),
                ),
              ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArenaSceneHeader(title: 'Bilgi Akademisi & Havuz', description: '${ctrl.totalPoolCount} gömülü & üretilen soru · Tekrar kartları · Çevrimdışı paketler', scene: _section == 2 ? 'notebook' : 'academy'),
              const SizedBox(height: 12),
              ArenaScrollPills<int>(
                items: const [0, 1, 2, 3, 4],
                selected: _section,
                labelBuilder: (idx) {
                  switch (idx) {
                    case 0:
                      return 'Havuz (${ctrl.totalPoolCount})';
                    case 1:
                      return 'Tekrar (${ctrl.reviewDeck.length})';
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
        return _buildSpacedRepetitionView(ctrl, accent);
      case 2:
        return _buildBookmarksView(ctrl, accent);
      case 3:
        return _buildPacksView(context, ctrl, accent);
      default:
        return _buildProfilesView(context, ctrl, accent);
    }
  }

  Widget _buildQuestionPoolBrowser(BuildContext context, ArenaController ctrl, Color accent) {
    final qLower = _query.trim().toLowerCase();
    final shown = <Question>[];
    final all = ctrl.allQuestions;
    final hasReportedFilter = _hideReported && ctrl.reportedQuestionIds.isNotEmpty;
    final isFastCountPath =
        qLower.isEmpty && _filterFormat == QuestionFormat.mixed && !hasReportedFilter;

    int matchCount = 0;
    if (isFastCountPath) {
      matchCount = ctrl.countForTopic(_filterTopic);
      for (var i = 0; i < all.length && shown.length < _visibleLimit; i++) {
        final q = all[i];
        if (_filterTopic != Topic.mixed && q.category != _filterTopic) continue;
        shown.add(q);
      }
    } else {
      for (var i = 0; i < all.length; i++) {
        final q = all[i];
        if (hasReportedFilter && ctrl.isReported(q)) continue;
        if (_filterTopic != Topic.mixed && q.category != _filterTopic) continue;
        if (!q.matchesFormat(_filterFormat)) continue;
        if (qLower.isNotEmpty) {
          final inText = q.text.toLowerCase().contains(qLower) ||
              q.explanation.toLowerCase().contains(qLower) ||
              q.options.any((o) => o.toLowerCase().contains(qLower));
          if (!inText) continue;
        }
        matchCount++;
        if (shown.length < _visibleLimit) {
          shown.add(q);
        }
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: shown.length + 2,
      itemBuilder: (ctx, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Stats Strip
              ArenaGlassCard(
                tint: accent,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: _miniStat('Toplam', '${ctrl.totalPoolCount}', accent)),
                    Expanded(
                      child: _miniStat(
                        'Görsel',
                        '${ctrl.visualQuestionCount}',
                        const Color(0xFFF6C453),
                      ),
                    ),
                    Expanded(
                      child: _miniStat(
                        'Etkinlik',
                        '${ctrl.activityQuestionCount}',
                        const Color(0xFF5CE09B),
                      ),
                    ),
                    Expanded(
                      child: _miniStat(
                        'Çözülen',
                        '${ctrl.playedQuestionIds.length}',
                        const Color(0xFFC5A3FF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() {
                  _query = v;
                  _visibleLimit = 30;
                }),
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: '${ctrl.totalPoolCount} soru, şık veya açıklamada ara...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: accent, size: 20),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ArenaScrollPills<Topic>(
                items: [Topic.mixed, ...Topic.poolCategories],
                selected: _filterTopic,
                labelBuilder: (t) => '${t.label} (${ctrl.countForTopic(t)})',
                onSelected: (t) => setState(() {
                  _filterTopic = t;
                  _visibleLimit = 30;
                }),
                accent: accent,
              ),
              const SizedBox(height: 8),
              ArenaScrollPills<QuestionFormat>(
                items: QuestionFormat.values,
                selected: _filterFormat,
                labelBuilder: (f) => f.label,
                onSelected: (f) => setState(() {
                  _filterFormat = f;
                  _visibleLimit = 30;
                }),
                accent: accent,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$matchCount eşleşen soru',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() => _hideReported = !_hideReported),
                    child: Text(
                      _hideReported ? 'Gizlenenleri Göster' : 'Gizlenenleri Sakla',
                      style: TextStyle(fontSize: 11.5, color: accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          );
        }

        if (index == shown.length + 1) {
          if (shown.length >= matchCount) return const SizedBox(height: 16);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _visibleLimit += 40),
              icon: const Icon(Icons.expand_more_rounded),
              label: Text('Daha Fazla Göster (${matchCount - shown.length} kaldı)'),
            ),
          );
        }

        final q = shown[index - 1];
        final expanded = _expandedQuestionIds.contains(q.id);
        final bookmarked = ctrl.isBookmarked(q);
        final reported = ctrl.isReported(q);

        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
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
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.asset(q.category.detailImage, width: 38, height: 30,
                              cacheWidth: 120, fit: BoxFit.cover, excludeFromSemantics: true),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: q.category.accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(99),
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
                          Text(
                            q.difficulty.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: q.difficulty.color,
                            ),
                          ),
                          if (q.exam != null)
                            Text(
                              '· ${q.exam!.label}${q.lesson != null ? " / ${q.lesson}" : ""}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                            ),
                          if (q.visual != null)
                            Icon(Icons.bar_chart_rounded, size: 14, color: accent),
                          if (q.activity != null)
                            Text(
                              '· ${q.activity!.kind.badgeLabel}',
                              style: TextStyle(fontSize: 11, color: accent),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => ctrl.toggleBookmark(q),
                      child: Icon(
                        bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        size: 19,
                        color: bookmarked ? const Color(0xFFF6C453) : Colors.white60,
                      ),
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
                  ),
                ),
                if (expanded) ...[
                  if (q.visual != null)
                    QuestionVisualViewer(visual: q.visual!, accent: q.category.accent),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5CE09B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF5CE09B).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Doğru Yanıt: ${q.correctAnswerText}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF5CE09B),
                          ),
                        ),
                        if (q.explanation.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            q.explanation,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => ctrl.toggleReportQuestion(q),
                        icon: Icon(
                          reported ? Icons.visibility_rounded : Icons.flag_outlined,
                          size: 15,
                        ),
                        label: Text(
                          reported ? 'Havuzda Geri Aç' : 'Sorunu İşaretle / Gizle',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpacedRepetitionView(ArenaController ctrl, Color accent) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        ArenaGlassCard(
          tint: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology_alt_rounded, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    '${ctrl.dueReviewCards.length} soru tekrar zamanında',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Yanlış veya boş bıraktığın sorular Leitner kutularına eklenir (5dk → 1g → 3g → 7g → 14g → 30g).',
                style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.72)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: ctrl.reviewDeck.isEmpty
                    ? null
                    : () => ctrl.startSpacedRepetitionReview(),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF06101F),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Tekrar Turunu Başlat'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (ctrl.reviewDeck.isEmpty)
          _emptyBox(
            'Tekrar defterin tertemiz',
            'Bir tur oynadığında zorlandığın sorular otomatik olarak buraya eklenir.',
            Icons.auto_stories_rounded,
            accent,
          ),
        for (final card in ctrl.reviewDeck)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ArenaGlassCard(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Kutu ${card.box + 1} · ${card.question.category.label}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${card.attempts} deneme · ${card.correct} doğru',
                        style: const TextStyle(fontSize: 11, color: Colors.white60),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.question.text,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBookmarksView(ArenaController ctrl, Color accent) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        if (ctrl.savedBookmarks.isEmpty)
          _emptyBox(
            'Bilgi Defterin Hazır',
            'Oyun sırasında veya Havuz sekmesinde yer işareti simgesine dokunarak favori sorularını burada topla.',
            Icons.bookmark_added_rounded,
            accent,
          ),
        for (final q in ctrl.savedBookmarks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ArenaGlassCard(
              tint: q.category.accent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        q.category.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: q.category.accent,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => ctrl.toggleBookmark(q),
                        icon: const Icon(Icons.bookmark_remove_rounded,
                            color: Color(0xFFF6C453), size: 20),
                      ),
                    ],
                  ),
                  Text(
                    q.text,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Yanıt: ${q.correctAnswerText}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF5CE09B),
                    ),
                  ),
                  if (q.explanation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      q.explanation,
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.78)),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPacksView(BuildContext context, ArenaController ctrl, Color accent) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        ArenaGlassCard(
          tint: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Soru Paketi Aktarımı (JSON)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                'JSON soru paketlerini içe aktarabilir, mükerrer kontrolünden geçirebilir veya tek dokunuşla geri alabilirsin.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.72)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final msg = await ctrl.importJsonQuestionPacks();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: const Color(0xFF06101F),
                      ),
                      icon: const Icon(Icons.file_open_rounded, size: 18),
                      label: const Text('JSON İçe Aktar'),
                    ),
                  ),
                  if (ctrl.lastImportedPackId != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        ctrl.undoLastImport();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Son içe aktarım geri alındı.')),
                        );
                      },
                      icon: const Icon(Icons.undo_rounded, size: 17),
                      label: const Text('Geri Al'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (ctrl.offlinePacks.isEmpty)
          _emptyBox(
            'Çevrimdışı Paket Arşivin',
            'AI & Modeller sekmesinden ürettiğin ya da JSON ile içe aktardığın soru paketleri burada çevrimdışı saklanır.',
            Icons.inventory_2_rounded,
            accent,
          ),
        for (final pack in ctrl.offlinePacks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ArenaGlassCard(
              tint: accent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${pack.questions.length} soru · ${pack.models.join(" · ")}',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.68)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => ctrl.startPackRound(pack),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: const Color(0xFF06101F),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Oyna'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => ctrl.exportQuestionPack(pack),
                        icon: const Icon(Icons.download_rounded, size: 17),
                        label: const Text('JSON Kaydet'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfilesView(BuildContext context, ArenaController ctrl, Color accent) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        FilledButton.icon(
          onPressed: () => _showCreateProfileSheet(context),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: const Color(0xFF06101F),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Yeni TYT / AYT / KPSS / LGS Profili Ekle',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 12),
        for (final p in ctrl.studyProfiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ArenaGlassCard(
              tint: Topic.exam.accent,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${p.exam.label} · ${p.lesson} · ${p.difficulty.label} · ${p.questionCount} Soru',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => ctrl.deleteStudyProfile(p.id),
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
                  ),
                  FilledButton(
                    onPressed: () => ctrl.startStudyProfileRound(p),
                    style: FilledButton.styleFrom(
                      backgroundColor: Topic.exam.accent,
                      foregroundColor: const Color(0xFF06101F),
                    ),
                    child: const Text('Başla'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.68)),
        ),
      ],
    );
  }

  Widget _emptyBox(String title, String subtitle, IconData icon, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
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
