import 'dart:math';
import 'package:flutter/material.dart';
import '../models/quiz_models.dart';
import '../services/ai_gateway_service.dart';
import '../state/arena_controller.dart';
import '../theme/arena_design.dart';
import '../widgets/question_renderers.dart';

class QuizSessionScreen extends StatefulWidget {
  final ArenaController controller;
  const QuizSessionScreen({super.key, required this.controller});

  @override
  State<QuizSessionScreen> createState() => _QuizSessionScreenState();
}

class _QuizSessionScreenState extends State<QuizSessionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeCtrl;
  String? _lastAnimatedAnswerKey;
  String? _coachQuestionId;
  String? _coachReply;
  bool _coachLoading = false;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _askCoach(Question q, String style) async {
    widget.controller.setOverlayPause(true);
    setState(() {
      _coachQuestionId = q.id;
      _coachLoading = true;
    });
    final reply = await AiGatewayService.askLearningCoach(
      config: widget.controller.aiConfig,
      question: q,
      promptStyle: style,
    );
    if (!mounted) return;
    setState(() {
      _coachReply = reply;
      _coachLoading = false;
    });
  }

  Future<void> _triggerSingleVoiceAnswer(BuildContext context, {bool pronunciation = false}) async {
    final err = await widget.controller.listenOnceAndResolveCurrentQuestion(
      isPronunciation: pronunciation,
    );
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 3)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final round = ctrl.activeRound;
    if (round == null) return const SizedBox.shrink();

    final wp = ctrl.currentWallpaper;
    final accent = wp.primary;

    if (round.finished) {
      return _buildResultScreen(context, ctrl, round, accent);
    }

    if (round.waitingStageBreak) {
      return _buildStageBreakScreen(ctrl, round, accent);
    }

    final q = round.current;
    if (_coachQuestionId != q.id) {
      _coachQuestionId = null;
      _coachReply = null;
      _coachLoading = false;
    }

    // Trigger wrong-answer shake once per question
    if (round.revealed && round.answers.isNotEmpty) {
      final last = round.answers.last;
      final key = '${round.id}_${round.currentIndex}';
      if (_lastAnimatedAnswerKey != key) {
        _lastAnimatedAnswerKey = key;
        if (!last.correct && !ctrl.reduceMotion) {
          _shakeCtrl.forward(from: 0);
        }
      }
    }

    final bookmarked = ctrl.isBookmarked(q);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ctrl.togglePauseRound();
      },
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top HUD Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: ctrl.togglePauseRound,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                        ),
                        icon: Icon(
                          round.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              round.setup.mode == GameMode.stages
                                  ? round.currentStageLabel
                                  : round.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                            Text(
                              'Soru ${round.currentIndex + 1} / ${round.questions.length} · ${round.totalScore}p',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (round.streak >= 2)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9559).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'x${round.streak}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFF9559),
                            ),
                          ),
                        ),
                      IconButton(
                        onPressed: () => ctrl.toggleBookmark(q),
                        icon: Icon(
                          bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                          color: bookmarked ? const Color(0xFFF6C453) : Colors.white70,
                          size: 21,
                        ),
                      ),
                      CountdownRing(
                        remainingSeconds: round.remainingSeconds,
                        totalSeconds: round.totalTimerSeconds,
                        accent: accent,
                      ),
                    ],
                  ),
                ),

                // Progress linear strip
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: (round.currentIndex + 1) / max(1, round.questions.length),
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                ),

                // Duel Scoreboard Banner if active
                if (round.isDuel) _buildDuelBanner(round, accent),
                if (round.hasRivals) _buildRivalBanner(round),

                // Scrollable Question + Options + Coach Area
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      AnimatedBuilder(
                        animation: _shakeCtrl,
                        builder: (ctx, child) {
                          final dx = sin(_shakeCtrl.value * pi * 4) *
                              (1.0 - _shakeCtrl.value) *
                              10.0;
                          return Transform.translate(offset: Offset(dx, 0), child: child);
                        },
                        child: ArenaGlassCard(
                          tint: q.category.accent,
                          highContrast: ctrl.highContrast,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ClipRRect(borderRadius: BorderRadius.circular(8),
                                    child: Image.asset(q.category.detailImage, width: 38, height: 36,
                                      fit: BoxFit.cover, excludeFromSemantics: true)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: q.category.accent.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        q.exam != null
                                            ? '${q.exam!.label} · ${q.lesson ?? q.category.label}'
                                            : q.category.label,
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
                                  Text(
                                    q.difficulty.label,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: q.difficulty.color,
                                    ),
                                  ),
                                  const Spacer(),
                                  InkWell(
                                    onTap: ctrl.narrateCurrentQuestion,
                                    child: Icon(
                                      Icons.volume_up_rounded,
                                      size: 19,
                                      color: Colors.white.withValues(alpha: 0.72),
                                    ),
                                  ),
                                ],
                              ),
                              if (q.bloom != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    [if (q.studyLevel != null) q.studyLevel!, q.bloom!.label, q.responseType.label].join(' · '),
                                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Text(
                                q.text,
                                style: TextStyle(
                                  fontSize: 17.0 * ctrl.readingScale,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.32,
                                ),
                              ),
                              if (q.visual != null)
                                QuestionVisualViewer(
                                  visual: q.visual!,
                                  accent: q.category.accent,
                                  onZoomStart: () => ctrl.setOverlayPause(true),
                                  onZoomEnd: () => ctrl.setOverlayPause(false),
                                ),
                              if (q.activity != null)
                                QuestionActivityWidget(
                                  key: ValueKey(q.id),
                                  question: q,
                                  accent: q.category.accent,
                                  revealed: round.revealed,
                                  onPlayListeningAudio: () => ctrl.speakActivityAudio(q),
                                  onStartPronunciationMic: () =>
                                      _triggerSingleVoiceAnswer(context, pronunciation: true),
                                  onSubmitSequence: (seq) => ctrl.submitActivitySequence(seq),
                                  onSelectChoice: (idx) => ctrl.submitChoice(idx),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (q.creation != null) ...[
                        ArenaGlassCard(
                          tint: accent,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(q.creation!.brief, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              for (final criterion in q.creation!.criteria)
                                Text('• $criterion', style: const TextStyle(color: Colors.white70)),
                              if (round.needsCreation)
                                _WrittenInput(
                                  key: ValueKey('design-${q.id}'),
                                  label: 'Çözümün veya tasarımın',
                                  action: 'Tasarımımı kaydet ve kontrol sorusuna geç',
                                  initial: ctrl.creationPortfolio[q.id] ?? '',
                                  long: true,
                                  onSubmit: ctrl.saveCreationResponse,
                                )
                              else ...[
                                const SizedBox(height: 8),
                                SelectableText(round.creationResponse, style: const TextStyle(color: Colors.white)),
                                const SizedBox(height: 8),
                                const Text('Tasarımın defterine kaydedildi. Tur puanı aşağıdaki kontrol sorusuna göre hesaplanır.',
                                  style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (q.multiSelect != null)
                        _MultipleAnswerInput(key: ValueKey(q.id), task: q.multiSelect!,
                            revealed: round.revealed, onSubmit: ctrl.submitMultiple),
                      if (q.responseType == ResponseType.fill && !round.revealed)
                        _WrittenInput(
                          key: ValueKey('fill-${q.id}'),
                          label: 'Yanıtını yaz (varsa birimiyle)',
                          action: 'Yanıtı kontrol et',
                          onSubmit: ctrl.submitWrittenAnswer,
                        ),
                      if (!round.needsCreation && q.multiSelect == null && !q.isInteractiveSequence &&
                          q.responseType != ResponseType.fill)
                        for (var i = 0; i < q.options.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: _buildOptionTile(ctrl, round, q, i, accent),
                          ),

                      // Revealed Explanation & AI Coach Card
                      if (round.revealed) ...[
                        const SizedBox(height: 6),
                        _buildPostAnswerPanel(ctrl, round, q, accent),
                      ],
                    ],
                  ),
                ),

                // Bottom Bar: Live Voice Host Bar OR Jokers + Voice Button OR Next Question
                _buildBottomActionBar(context, ctrl, round, q, accent),
              ],
            ),

            // Pause Overlay
            if (round.paused) _buildPauseModal(ctrl, accent),
          ],
        ),
      ),
    );
  }

  Widget _buildDuelBanner(ActiveRound round, Color accent) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9559).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF9559).withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_rounded, size: 17, color: Color(0xFFFF9559)),
          const SizedBox(width: 7),
          Text(
            'Sıra: ${round.activeDuelPlayerName}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          for (var i = 0; i < round.setup.duelPlayerNames.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${round.setup.duelPlayerNames[i]}: ${round.duelScores[i]}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: i == round.activeDuelPlayerIndex
                      ? FontWeight.w900
                      : FontWeight.w600,
                  color: i == round.activeDuelPlayerIndex
                      ? const Color(0xFFFFB454)
                      : Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRivalBanner(ActiveRound round) {
    final satirlar = <(String, int)>[
      ('Sen', round.totalScore),
      for (var i = 0; i < round.setup.rivalNames.length; i++) (round.setup.rivalNames[i], round.rivalScores[i]),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF12C25A).withValues(alpha: .16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF12C25A).withValues(alpha: .5)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (var i = 0; i < satirlar.length; i++)
            Text('${i + 1}. ${satirlar[i].$1}: ${satirlar[i].$2}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: satirlar[i].$1 == 'Sen' ? FontWeight.w900 : FontWeight.w600,
                  color: satirlar[i].$1 == 'Sen' ? const Color(0xFF8DD14F) : Colors.white70,
                )),
        ],
      ),
    );
  }

  Widget _buildOptionTile(
    ArenaController ctrl,
    ActiveRound round,
    Question q,
    int idx,
    Color accent,
  ) {
    final hidden = round.hiddenOptions.contains(idx) && !round.revealed;
    if (hidden) {
      return Opacity(
        opacity: 0.25,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: const Text(
            '50:50 ile elendi',
            style: TextStyle(fontSize: 13, color: Colors.white54),
          ),
        ),
      );
    }

    const letters = ['A', 'B', 'C', 'D'];
    final lastAns = round.revealed && round.answers.isNotEmpty ? round.answers.last : null;
    final isCorrectOpt = idx == q.answer;
    final isSelectedOpt = lastAns?.selectedOption == idx;

    Color borderColor = Colors.white.withValues(alpha: 0.14);
    Color bgColor = const Color(0xCC0E1A30);
    Color badgeColor = accent.withValues(alpha: 0.18);
    Color badgeText = accent;

    if (round.revealed) {
      if (isCorrectOpt) {
        borderColor = const Color(0xFF5CE09B);
        bgColor = const Color(0xFF5CE09B).withValues(alpha: 0.20);
        badgeColor = const Color(0xFF5CE09B);
        badgeText = const Color(0xFF06101F);
      } else if (isSelectedOpt) {
        borderColor = const Color(0xFFFF6B7A);
        bgColor = const Color(0xFFFF6B7A).withValues(alpha: 0.20);
        badgeColor = const Color(0xFFFF6B7A);
        badgeText = Colors.white;
      }
    }

    return ArenaPressDepth(child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: round.revealed ? null : () => ctrl.submitChoice(idx),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color.alphaBlend(badgeColor.withValues(alpha: .19), const Color(0xff192c40)),Color.alphaBlend(bgColor,const Color(0xff101825))]),
            boxShadow: const [BoxShadow(color: Color(0xaa03070c), offset: Offset(0,3))],
            border: Border.all(
              color: borderColor,
              width: round.revealed && (isCorrectOpt || isSelectedOpt) ? 1.7 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  letters[idx % 4],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: badgeText,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  q.options[idx],
                  style: TextStyle(
                    fontSize: 14.5 * ctrl.readingScale,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (round.revealed && isCorrectOpt)
                const Icon(Icons.check_circle_rounded, color: Color(0xFF5CE09B), size: 20)
              else if (round.revealed && isSelectedOpt && !isCorrectOpt)
                const Icon(Icons.cancel_rounded, color: Color(0xFFFF6B7A), size: 20),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildPostAnswerPanel(
    ArenaController ctrl,
    ActiveRound round,
    Question q,
    Color accent,
  ) {
    final rec = round.answers.isNotEmpty ? round.answers.last : null;
    final ok = rec?.correct ?? false;
    final statusColor = ok ? const Color(0xFF5CE09B) : const Color(0xFFFF7B89);

    return ArenaGlassCard(
      tint: statusColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.verified_rounded : Icons.info_rounded,
                color: statusColor,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? 'Doğru Yanıt! (+${rec?.earnedPoints ?? 0} Puan)'
                      : 'Doğru Yanıt: ${q.correctAnswerText}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (q.responseType == ResponseType.fill && rec?.writtenResponse != null)
            Text('Yazdığın yanıt: ${rec!.writtenResponse}',
                style: const TextStyle(color: Colors.white70)),
          if (rec?.spokenTranscript != null && rec!.spokenTranscript!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Sesli yanıtın: "${rec.spokenTranscript}"',
              style: const TextStyle(fontSize: 11.5, color: Colors.white60),
            ),
          ],
          if (q.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              q.explanation,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.88),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'AI Öğrenme Koçu',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _coachChip('Daha basit anlat', () => _askCoach(q, 'Daha basit anlat'), accent),
                const SizedBox(width: 6),
                _coachChip('Örnek ver', () => _askCoach(q, 'Günlük hayattan örnek ver'), accent),
                const SizedBox(width: 6),
                _coachChip('Nasıl aklımda tutarım?', () => _askCoach(q, 'Nasıl aklımda tutarım?'), accent),
              ],
            ),
          ),
          if (_coachLoading) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Öğrenme Koçu yanıt hazırlıyor...',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ] else if (_coachReply != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Text(
                _coachReply!,
                style: const TextStyle(fontSize: 12.5, color: Colors.white, height: 1.36),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _coachChip(String label, VoidCallback onTap, Color accent) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 13, color: accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(
    BuildContext context,
    ArenaController ctrl,
    ActiveRound round,
    Question q,
    Color accent,
  ) {
    if (round.revealed) {
      final isLast = round.currentIndex + 1 >= round.questions.length;
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xE6081020),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              ctrl.setOverlayPause(false);
              ctrl.nextQuestion();
            },
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF06101F),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: Icon(isLast ? Icons.emoji_events_rounded : Icons.arrow_forward_rounded),
            label: Text(
              isLast ? 'Sonuçları Gör' : 'Sonraki Soru',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      );
    }

    if (round.needsCreation || q.multiSelect != null || q.responseType == ResponseType.fill) {
      return const SizedBox.shrink();
    }
    if (round.setup.liveVoiceHost) {
      return _buildLiveVoiceStudioBar(ctrl, accent);
    }

    final jokersAllowed = round.setup.mode.allowsJokers;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xE6081020),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          if (jokersAllowed) ...[
            _jokerButton(
              label: '50:50',
              icon: Icons.contrast_rounded,
              used: round.jokerFiftyUsed || q.responseType != ResponseType.choice || q.options.length < 4,
              onTap: ctrl.useFiftyFiftyJoker,
            ),
            const SizedBox(width: 6),
            _jokerButton(
              label: '+15sn',
              icon: Icons.more_time_rounded,
              used: round.jokerTimeUsed || round.totalTimerSeconds <= 0,
              onTap: ctrl.useExtraTimeJoker,
            ),
            const SizedBox(width: 6),
            _jokerButton(
              label: 'Pas',
              icon: Icons.skip_next_rounded,
              used: round.jokerSkipUsed,
              onTap: ctrl.useSkipJoker,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: ctrl.livePhase == LiveVoicePhase.listening
                  ? null
                  : () => _triggerSingleVoiceAnswer(
                        context,
                        pronunciation: q.isPronunciation,
                      ),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: const Color(0xFF06101F),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              icon: Icon(
                ctrl.livePhase == LiveVoicePhase.listening
                    ? Icons.graphic_eq_rounded
                    : Icons.mic_rounded,
                size: 16,
              ),
              label: Text(
                ctrl.livePhase == LiveVoicePhase.listening ? 'Dinliyor...' : 'Sesle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _jokerButton({
    required String label,
    required IconData icon,
    required bool used,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: used ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: used ? 0.35 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: const Color(0xFFF6C453)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveVoiceStudioBar(ArenaController ctrl, Color accent) {
    String statusTitle;
    switch (ctrl.livePhase) {
      case LiveVoicePhase.speakingQuestion:
        statusTitle = 'Sunucu soruyu okuyor...';
        break;
      case LiveVoicePhase.listening:
        statusTitle = 'Seni dinliyorum (A, B, C, D veya yanıtı söyle)';
        break;
      case LiveVoicePhase.reviewing:
        statusTitle = '${ctrl.livePreview} · ${ctrl.liveReviewCountdown} sn içinde gönderiliyor';
        break;
      case LiveVoicePhase.speakingFeedback:
        statusTitle = 'Sunucu sonucu açıklıyor...';
        break;
      case LiveVoicePhase.error:
        statusTitle = ctrl.liveError ?? 'Ses anlaşılamadı';
        break;
      default:
        statusTitle = 'Canlı Sesli Stüdyo Hazır';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xF0081122),
        border: Border(top: BorderSide(color: accent.withValues(alpha: 0.35))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.mic_external_on_rounded, color: accent, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              TextButton(
                onPressed: ctrl.retryLiveListening,
                child: const Text('Yeniden Dinle', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (ctrl.livePhase == LiveVoicePhase.listening)
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: ctrl.micLevel.clamp(0.08, 1.0),
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStageBreakScreen(ArenaController ctrl, ActiveRound round, Color accent) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ArenaGlassCard(
            tint: accent,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stairs_rounded, size: 48, color: accent),
                const SizedBox(height: 14),
                Text(
                  round.currentStageLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Şu ana kadar ${round.totalScore} puan topladın. Yeni etapta soru süren hızlanıyor!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.76)),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: ctrl.continueFromStageBreak,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: const Color(0xFF06101F),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                  ),
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text(
                    'Yeni Etaba Başla',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPauseModal(ArenaController ctrl, Color accent) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.76),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ArenaGlassCard(
            tint: accent,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tur Duraklatıldı',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: ctrl.togglePauseRound,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: const Color(0xFF06101F),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Yarışmaya Devam Et'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: ctrl.exitRound,
                  icon: const Icon(Icons.exit_to_app_rounded),
                  label: const Text('Ana Ekrana Dön'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultScreen(
    BuildContext context,
    ArenaController ctrl,
    ActiveRound round,
    Color accent,
  ) {
    final correctCount = round.answers.where((a) => a.correct).length;
    final accuracy = round.questions.isEmpty
        ? 0
        : ((correctCount / round.questions.length) * 100).round();
    final missed = round.answers.where((a) => !a.correct).toList();

    return SafeArea(
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
            children: [
              ArenaGlassCard(
                tint: accent,
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: const Color(0xFFF6C453).withValues(alpha: 0.2),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        size: 40,
                        color: Color(0xFFF6C453),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      round.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: round.totalScore.toDouble()),
                      duration: const Duration(milliseconds: 900),
                      builder: (_, val, _) => Text(
                        '${val.round()} Puan',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _resStat('Doğru', '$correctCount/${round.questions.length}'),
                        _resStat('Başarı', '%$accuracy'),
                        _resStat('En İyi Seri', 'x${round.maxStreak}'),
                        _resStat('Seviye', '${ctrl.level}'),
                      ],
                    ),
                  ],
                ),
              ),

              if ((round.isDuel || round.hasRivals) && ctrl.history.isNotEmpty) ...[
                const SizedBox(height: 14),
                ArenaGlassCard(
                  tint: const Color(0xFFFFB454),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        round.hasRivals ? 'Sıralama' : 'Düello Kürsüsü',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (var i = 0; i < ctrl.history.first.duelStandings.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Text(
                                '${i + 1}. ${ctrl.history.first.duelStandings[i]["name"]}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: i == 0 ? const Color(0xFFF6C453) : Colors.white,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${ctrl.history.first.duelStandings[i]["score"]} puan (${ctrl.history.first.duelStandings[i]["correct"]} doğru)',
                                style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => ctrl.startConfiguredRound(
                        customTitle: round.title,
                        overrideSetup: round.setup,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: const Color(0xFF06101F),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text(
                        'Yeni Tur',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: ctrl.exitRound,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const Icon(Icons.home_rounded),
                      label: const Text('Ana Ekran'),
                    ),
                  ),
                ],
              ),

              if (missed.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Gözden Geçirilecek Sorular (${missed.length})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                for (final m in missed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: ArenaGlassCard(
                      padding: const EdgeInsets.all(13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.question.text,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Doğru: ${m.question.correctAnswerText}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF5CE09B),
                            ),
                          ),
                          if (m.question.explanation.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              m.question.explanation,
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
          ConfettiCelebrationOverlay(active: !ctrl.reduceMotion && accuracy >= 50),
        ],
      ),
    );
  }

  Widget _resStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white60),
        ),
      ],
    );
  }
}

class _WrittenInput extends StatefulWidget {
  final String label;
  final String action;
  final String initial;
  final bool long;
  final ValueChanged<String> onSubmit;
  const _WrittenInput({super.key, required this.label, required this.action,
      required this.onSubmit, this.initial = '', this.long = false});

  @override
  State<_WrittenInput> createState() => _WrittenInputState();
}

class _WrittenInputState extends State<_WrittenInput> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    FocusScope.of(context).unfocus();
    widget.onSubmit(value);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(controller: _text, minLines: widget.long ? 3 : 1,
        maxLines: widget.long ? 8 : 1, autocorrect: false,
        style: const TextStyle(color: Colors.white),
        onChanged: (_) => setState(() {}),
        onSubmitted: widget.long ? null : (_) => _send(),
        decoration: InputDecoration(labelText: widget.label),
      ),
      const SizedBox(height: 8),
      FilledButton(onPressed: _text.text.trim().isEmpty ? null : _send,
        child: Text(widget.action)),
    ],
  );
}

class _MultipleAnswerInput extends StatefulWidget {
  final MultiSelectTask task;
  final bool revealed;
  final ValueChanged<Set<int>> onSubmit;
  const _MultipleAnswerInput({super.key, required this.task, required this.revealed, required this.onSubmit});

  @override
  State<_MultipleAnswerInput> createState() => _MultipleAnswerInputState();
}

class _MultipleAnswerInputState extends State<_MultipleAnswerInput> {
  final selected = <int>{};

  @override
  Widget build(BuildContext context) => Column(children: [
    const Align(alignment: Alignment.centerLeft, child: Text('Geçerli önermelerin tümünü seç.')),
    for (final (index, option) in widget.task.options.indexed)
      CheckboxListTile(
        title: Text(option), value: selected.contains(index),
        onChanged: widget.revealed ? null : (value) => setState(() {
          if (value == true) {selected.add(index);} else {selected.remove(index);}
        }),
      ),
    if (!widget.revealed)
      FilledButton(onPressed: selected.isEmpty ? null : () => widget.onSubmit(Set.of(selected)),
        child: const Text('Seçimlerimi kontrol et')),
  ]);
}
