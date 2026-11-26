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

    const accent = StudioPalette.gold;

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
                // Zirve Merdiveni Stüdyo Üst HUD Barı
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Row(
                    children: [
                      ArenaPressDepth(
                        depthOffset: 1.5,
                        child: IconButton(
                          onPressed: ctrl.togglePauseRound,
                          style: IconButton.styleFrom(
                            backgroundColor: StudioPalette.navyTop.withValues(alpha: 0.85),
                            side: const BorderSide(color: StudioPalette.gold, width: 1.3),
                          ),
                          icon: Icon(
                            round.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                            color: StudioPalette.goldBright,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              colors: [StudioPalette.navyTop, StudioPalette.navyDark],
                            ),
                            border: Border.all(
                              color: StudioPalette.gold.withValues(alpha: 0.72),
                              width: 1.3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: StudioPalette.gold.withValues(alpha: 0.16),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                round.setup.mode == GameMode.stages
                                    ? round.currentStageLabel
                                    : round.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: StudioPalette.goldBright,
                                ),
                              ),
                              Text(
                                'Soru ${round.currentIndex + 1} / ${round.questions.length} · ${round.totalScore}p',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (round.streak >= 2)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [StudioPalette.amber, Color(0xFFCC6400)],
                            ),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: Colors.white70),
                          ),
                          child: Text(
                            'x${round.streak}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      IconButton(
                        onPressed: () => ctrl.toggleBookmark(q),
                        icon: Icon(
                          bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                          color: bookmarked ? StudioPalette.goldBright : Colors.white70,
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

                // Altın stüdyo ilerleme şeridi
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: (round.currentIndex + 1) / max(1, round.questions.length),
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(StudioPalette.gold),
                    ),
                  ),
                ),

                if (round.isDuel) _buildDuelBanner(round, accent),
                if (round.hasRivals) _buildRivalBanner(round),

                // Soru Plaketi + 3D Altıgen Seçenekler + AI Koç
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                    children: [
                      AnimatedBuilder(
                        animation: _shakeCtrl,
                        builder: (ctx, child) {
                          final dx = sin(_shakeCtrl.value * pi * 4) *
                              (1.0 - _shakeCtrl.value) *
                              10.0;
                          return Transform.translate(offset: Offset(dx, 0), child: child);
                        },
                        child: Studio3DEntrance(
                          key: ValueKey('quiz_q_${q.id}_${round.currentIndex}'),
                          child: Studio3DPlaque(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                            chamfer: 16,
                            borderColor: ctrl.highContrast ? StudioPalette.goldBright : StudioPalette.gold,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.asset(
                                        q.category.detailImage,
                                        width: 34,
                                        height: 32,
                                        fit: BoxFit.cover,
                                        excludeFromSemantics: true,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 3.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: StudioPalette.gold.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(99),
                                          border: Border.all(
                                            color: StudioPalette.gold.withValues(alpha: 0.55),
                                          ),
                                        ),
                                        child: Text(
                                          q.exam != null
                                              ? '${q.exam!.label} · ${q.lesson ?? q.category.label}'
                                              : q.category.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: StudioPalette.goldBright,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      q.difficulty.label,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w900,
                                        color: q.difficulty.color,
                                      ),
                                    ),
                                    const Spacer(),
                                    InkWell(
                                      onTap: ctrl.narrateCurrentQuestion,
                                      child: const Icon(
                                        Icons.volume_up_rounded,
                                        size: 20,
                                        color: StudioPalette.goldBright,
                                      ),
                                    ),
                                  ],
                                ),
                                if (q.bloom != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 7),
                                    child: Text(
                                      [
                                        if (q.studyLevel != null) q.studyLevel!,
                                        q.bloom!.label,
                                        q.responseType.label,
                                      ].join(' · '),
                                      style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Text(
                                  q.text,
                                  style: TextStyle(
                                    fontSize: 17.2 * ctrl.readingScale,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.34,
                                  ),
                                ),
                                if (q.visual != null)
                                  QuestionVisualViewer(
                                    visual: q.visual!,
                                    accent: StudioPalette.gold,
                                    onZoomStart: () => ctrl.setOverlayPause(true),
                                    onZoomEnd: () => ctrl.setOverlayPause(false),
                                  ),
                                if (q.activity != null)
                                  QuestionActivityWidget(
                                    key: ValueKey(q.id),
                                    question: q,
                                    accent: StudioPalette.gold,
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
                      ),
                      const SizedBox(height: 14),

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
                                const Text(
                                  'Tasarımın defterine kaydedildi. Tur puanı aşağıdaki kontrol sorusuna göre hesaplanır.',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (q.multiSelect != null)
                        _MultipleAnswerInput(
                          key: ValueKey(q.id),
                          task: q.multiSelect!,
                          revealed: round.revealed,
                          onSubmit: ctrl.submitMultiple,
                        ),
                      if (q.responseType == ResponseType.fill && !round.revealed)
                        _WrittenInput(
                          key: ValueKey('fill-${q.id}'),
                          label: 'Yanıtını yaz (varsa birimiyle)',
                          action: 'Yanıtı kontrol et',
                          onSubmit: ctrl.submitWrittenAnswer,
                        ),
                      if (!round.needsCreation &&
                          q.multiSelect == null &&
                          !q.isInteractiveSequence &&
                          q.responseType != ResponseType.fill)
                        for (var i = 0; i < q.options.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 11),
                            child: _buildOptionTile(ctrl, round, q, i),
                          ),

                      if (round.revealed) ...[
                        const SizedBox(height: 6),
                        _buildPostAnswerPanel(ctrl, round, q, accent),
                      ],
                    ],
                  ),
                ),

                _buildBottomActionBar(context, ctrl, round, q, accent),
              ],
            ),

            if (round.paused) _buildPauseModal(ctrl, accent),
          ],
        ),
      ),
    );
  }

  Widget _buildDuelBanner(ActiveRound round, Color accent) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [StudioPalette.navyTop, StudioPalette.navyDark]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StudioPalette.amber.withValues(alpha: 0.75), width: 1.3),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_rounded, size: 17, color: StudioPalette.goldBright),
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
                  fontWeight: i == round.activeDuelPlayerIndex ? FontWeight.w900 : FontWeight.w600,
                  color: i == round.activeDuelPlayerIndex ? StudioPalette.goldBright : Colors.white70,
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
      for (var i = 0; i < round.setup.rivalNames.length; i++)
        (round.setup.rivalNames[i], round.rivalScores[i]),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [StudioPalette.navyTop, StudioPalette.navyDark]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.65), width: 1.3),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (var i = 0; i < satirlar.length; i++)
            Text(
              '${i + 1}. ${satirlar[i].$1}: ${satirlar[i].$2}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: satirlar[i].$1 == 'Sen' ? FontWeight.w900 : FontWeight.w600,
                color: satirlar[i].$1 == 'Sen' ? StudioPalette.goldBright : Colors.white70,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionTile(
    ArenaController ctrl,
    ActiveRound round,
    Question q,
    int idx,
  ) {
    const letters = ['A', 'B', 'C', 'D'];
    final hidden = round.hiddenOptions.contains(idx) && !round.revealed;
    final lastAns = round.revealed && round.answers.isNotEmpty ? round.answers.last : null;
    final isCorrectOpt = idx == q.answer;
    final isSelectedOpt = lastAns?.selectedOption == idx;

    final StudioOptionState state;
    if (hidden) {
      state = StudioOptionState.hidden;
    } else if (round.revealed) {
      if (isCorrectOpt) {
        state = StudioOptionState.correct;
      } else if (isSelectedOpt) {
        state = StudioOptionState.wrong;
      } else {
        state = StudioOptionState.normal;
      }
    } else {
      state = StudioOptionState.normal;
    }

    return Studio3DOptionPlaque(
      letter: letters[idx % 4],
      text: hidden ? '50:50 ile elendi' : q.options[idx],
      state: state,
      fontSize: 14.8 * ctrl.readingScale,
      onTap: (round.revealed || hidden) ? null : () => ctrl.submitChoice(idx),
    );
  }

  Widget _buildPostAnswerPanel(
    ArenaController ctrl,
    ActiveRound round,
    Question q,
    Color accent,
  ) {
    final rec = round.answers.isNotEmpty ? round.answers.last : null;
    final ok = rec?.correct ?? false;
    final statusColor = ok ? const Color(0xFF4BE085) : const Color(0xFFFF7B89);

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
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? 'Doğru Yanıt! (+${rec?.earnedPoints ?? 0} Puan)'
                      : 'Doğru Yanıt: ${q.correctAnswerText}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
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
                color: Colors.white.withValues(alpha: 0.9),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'AI Öğrenme Koçu',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: StudioPalette.goldBright,
            ),
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
                color: StudioPalette.navyDark.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.45)),
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
    return ArenaPressDepth(
      depthOffset: 1.3,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [StudioPalette.navyTop, StudioPalette.navyDark]),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 13, color: StudioPalette.goldBright),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: StudioPalette.goldBright,
                ),
              ),
            ],
          ),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xEE0D175A), StudioPalette.night],
          ),
          border: Border(top: BorderSide(color: StudioPalette.gold, width: 1.4)),
        ),
        child: Studio3DButton(
          label: isLast ? 'Sonuçları Gör' : 'Sonraki Soru',
          icon: isLast ? Icons.emoji_events_rounded : Icons.arrow_forward_rounded,
          expand: true,
          fontSize: 15.5,
          onPressed: () {
            ctrl.setOverlayPause(false);
            ctrl.nextQuestion();
          },
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
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xEE0D175A), StudioPalette.night],
        ),
        border: Border(top: BorderSide(color: StudioPalette.gold, width: 1.3)),
      ),
      child: Row(
        children: [
          if (jokersAllowed) ...[
            Studio3DJokerOrb(
              label: '50:50',
              icon: Icons.contrast_rounded,
              used: round.jokerFiftyUsed ||
                  q.responseType != ResponseType.choice ||
                  q.options.length < 4,
              onTap: ctrl.useFiftyFiftyJoker,
            ),
            Studio3DJokerOrb(
              label: '+15sn',
              icon: Icons.more_time_rounded,
              used: round.jokerTimeUsed || round.totalTimerSeconds <= 0,
              onTap: ctrl.useExtraTimeJoker,
            ),
            Studio3DJokerOrb(
              label: 'Pas',
              icon: Icons.skip_next_rounded,
              used: round.jokerSkipUsed,
              onTap: ctrl.useSkipJoker,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Studio3DButton(
              label: ctrl.livePhase == LiveVoicePhase.listening ? 'Dinliyor...' : 'Sesle',
              icon: ctrl.livePhase == LiveVoicePhase.listening
                  ? Icons.graphic_eq_rounded
                  : Icons.mic_rounded,
              expand: true,
              shimmer: false,
              fontSize: 13,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              onPressed: ctrl.livePhase == LiveVoicePhase.listening
                  ? null
                  : () => _triggerSingleVoiceAnswer(
                        context,
                        pronunciation: q.isPronunciation,
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveVoiceStudioBar(ArenaController ctrl, Color accent) {
    final statusTitle = switch (ctrl.livePhase) {
      LiveVoicePhase.speakingQuestion => 'Sunucu soruyu okuyor...',
      LiveVoicePhase.listening => 'Seni dinliyorum (A, B, C, D veya yanıtı söyle)',
      LiveVoicePhase.reviewing =>
        '${ctrl.livePreview} · ${ctrl.liveReviewCountdown} sn içinde gönderiliyor',
      LiveVoicePhase.speakingFeedback => 'Sunucu sonucu açıklıyor...',
      LiveVoicePhase.error => ctrl.liveError ?? 'Ses anlaşılamadı',
      _ => 'Canlı Sesli Stüdyo Hazır',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF00D175A), StudioPalette.night],
        ),
        border: Border(top: BorderSide(color: StudioPalette.gold, width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.mic_external_on_rounded, color: StudioPalette.goldBright, size: 19),
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
                child: const Text('Yeniden Dinle',
                    style: TextStyle(fontSize: 12, color: StudioPalette.goldBright)),
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
                valueColor: const AlwaysStoppedAnimation<Color>(StudioPalette.gold),
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
          padding: const EdgeInsets.all(22),
          child: Studio3DPlaque(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Studio3DOrbitEmblem(icon: Icons.stairs_rounded, size: 74),
                const SizedBox(height: 14),
                Text(
                  round.currentStageLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: StudioPalette.goldBright,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Şu ana kadar ${round.totalScore} puan topladın. Yeni etapta soru süren hızlanıyor!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.84)),
                ),
                const SizedBox(height: 20),
                Studio3DButton(
                  label: 'Yeni Etaba Başla',
                  icon: Icons.bolt_rounded,
                  expand: true,
                  onPressed: ctrl.continueFromStageBreak,
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
      color: Colors.black.withValues(alpha: 0.78),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Studio3DPlaque(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tur Duraklatıldı',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: StudioPalette.goldBright,
                  ),
                ),
                const SizedBox(height: 18),
                Studio3DButton(
                  label: 'Yarışmaya Devam Et',
                  icon: Icons.play_arrow_rounded,
                  expand: true,
                  onPressed: ctrl.togglePauseRound,
                ),
                const SizedBox(height: 10),
                Studio3DButton(
                  label: 'Ana Ekrana Dön',
                  icon: Icons.exit_to_app_rounded,
                  variant: StudioButtonVariant.navy,
                  shimmer: false,
                  expand: true,
                  onPressed: ctrl.exitRound,
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
              Studio3DPlaque(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    const Studio3DOrbitEmblem(icon: Icons.emoji_events_rounded, size: 84),
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
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: StudioPalette.goldBright,
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
                  tint: StudioPalette.gold,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        round.hasRivals ? 'Sıralama' : 'Düello Kürsüsü',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: StudioPalette.goldBright,
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
                                  color: i == 0 ? StudioPalette.goldBright : Colors.white,
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
                    child: Studio3DButton(
                      label: 'Yeni Tur',
                      icon: Icons.replay_rounded,
                      expand: true,
                      onPressed: () => ctrl.startConfiguredRound(
                        customTitle: round.title,
                        overrideSetup: round.setup,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Studio3DButton(
                      label: 'Ana Ekran',
                      icon: Icons.home_rounded,
                      variant: StudioButtonVariant.navy,
                      shimmer: false,
                      expand: true,
                      onPressed: ctrl.exitRound,
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
                    fontWeight: FontWeight.w900,
                    color: StudioPalette.goldBright,
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
                              color: Color(0xFF4BE085),
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
  const _WrittenInput({
    super.key,
    required this.label,
    required this.action,
    required this.onSubmit,
    this.initial = '',
    this.long = false,
  });

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
          TextField(
            controller: _text,
            minLines: widget.long ? 3 : 1,
            maxLines: widget.long ? 8 : 1,
            autocorrect: false,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => setState(() {}),
            onSubmitted: widget.long ? null : (_) => _send(),
            decoration: InputDecoration(
              labelText: widget.label,
              filled: true,
              fillColor: StudioPalette.navyDark.withValues(alpha: 0.8),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: StudioPalette.gold.withValues(alpha: 0.45)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: StudioPalette.gold, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Studio3DButton(
            label: widget.action,
            expand: true,
            onPressed: _text.text.trim().isEmpty ? null : _send,
          ),
        ],
      );
}

class _MultipleAnswerInput extends StatefulWidget {
  final MultiSelectTask task;
  final bool revealed;
  final ValueChanged<Set<int>> onSubmit;
  const _MultipleAnswerInput({
    super.key,
    required this.task,
    required this.revealed,
    required this.onSubmit,
  });

  @override
  State<_MultipleAnswerInput> createState() => _MultipleAnswerInputState();
}

class _MultipleAnswerInputState extends State<_MultipleAnswerInput> {
  final selected = <int>{};

  @override
  Widget build(BuildContext context) => Column(children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Geçerli önermelerin tümünü seç.',
              style: TextStyle(color: StudioPalette.goldBright, fontWeight: FontWeight.w800)),
        ),
        for (final (index, option) in widget.task.options.indexed)
          CheckboxListTile(
            title: Text(option, style: const TextStyle(color: Colors.white)),
            activeColor: StudioPalette.gold,
            checkColor: StudioPalette.night,
            value: selected.contains(index),
            onChanged: widget.revealed
                ? null
                : (value) => setState(() {
                      if (value == true) {
                        selected.add(index);
                      } else {
                        selected.remove(index);
                      }
                    }),
          ),
        if (!widget.revealed)
          Studio3DButton(
            label: 'Seçimlerimi kontrol et',
            expand: true,
            onPressed: selected.isEmpty ? null : () => widget.onSubmit(Set.of(selected)),
          ),
      ]);
}
