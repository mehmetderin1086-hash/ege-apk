import 'dart:math';
import 'package:flutter/material.dart';
import '../models/quiz_models.dart';
import '../state/arena_controller.dart';
import '../theme/arena_design.dart';
import '../widgets/question_renderers.dart';
import 'zirve_screen.dart';

class ProgressTab extends StatefulWidget {
  final ArenaController controller;
  const ProgressTab({super.key, required this.controller});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

enum _MasteryFilter {
  all('Tümü'),
  active('Çözülenler'),
  weak('Zayıf (<%70)'),
  unexplored('Keşfedilmemiş');

  final String label;
  const _MasteryFilter(this.label);
}

enum _MasterySort {
  accuracyDesc('Doğruluk ↓'),
  answeredDesc('En Çok Çözülen'),
  weakFirst('Geliştirilecek ↑'),
  alpha('A–Z');

  final String label;
  const _MasterySort(this.label);
}

enum _BadgeFilter {
  all('Tümü'),
  unlocked('Kazanılan'),
  locked('Devam Eden'),
  akademi('Akademi'),
  ustalik('Ustalık'),
  zirve('Zirve');

  final String label;
  const _BadgeFilter(this.label);
}

enum _HistoryFilter {
  all('Tümü'),
  classic('Klasik'),
  training('Öğren'),
  sprint('Hız'),
  stages('Etaplı'),
  voice('Sesli'),
  duel('Düello');

  final String label;
  const _HistoryFilter(this.label);
}

class _ProgressTabState extends State<ProgressTab> {
  int _section = 0; // 0: Genel Bakış, 1: Alan Ustalığı, 2: Rozetler, 3: Geçmiş
  _MasteryFilter _masteryFilter = _MasteryFilter.all;
  _MasterySort _masterySort = _MasterySort.answeredDesc;
  String _masteryQuery = '';
  final _masterySearchCtrl = TextEditingController();
  _BadgeFilter _badgeFilter = _BadgeFilter.all;
  _HistoryFilter _historyFilter = _HistoryFilter.all;
  final Set<String> _expandedHistoryIds = {};

  @override
  void dispose() {
    _masterySearchCtrl.dispose();
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

  ({String title, String subtitle, IconData icon}) _rankForLevel(int level) {
    if (level >= 25) {
      return (
        title: 'Efsanevi Bilge',
        subtitle: 'İstanbul Zirvesi\'nin tartışmasız üstadı',
        icon: Icons.auto_awesome_rounded,
      );
    }
    if (level >= 15) {
      return (
        title: 'İstanbul Allamesi',
        subtitle: '23 alanda derin bilgi ve strateji ustası',
        icon: Icons.workspace_premium_rounded,
      );
    }
    if (level >= 10) {
      return (
        title: 'Zirve Ustası',
        subtitle: 'Yüksek doğruluk ve kararlı bilgi yürüyüşü',
        icon: Icons.emoji_events_rounded,
      );
    }
    if (level >= 6) {
      return (
        title: 'Boğaz Bilgini',
        subtitle: 'Birden çok alanda sağlam ustalık kuruyor',
        icon: Icons.school_rounded,
      );
    }
    if (level >= 3) {
      return (
        title: 'Akademi Yolcusu',
        subtitle: 'Merakla keşfeden, hızla yükselen öğrenci',
        icon: Icons.explore_rounded,
      );
    }
    return (
      title: 'Çırak Kaşif',
      subtitle: 'İstanbul Zirve Stüdyosu\'nda yolculuk başlıyor',
      icon: Icons.rocket_launch_rounded,
    );
  }

  String _sceneForSection() => switch (_section) {
        0 => 'duel_stage',
        1 => 'galata',
        2 => 'kiz_kulesi',
        _ => 'bogaz',
      };

  ({String label, Color color}) _tierForTopic(int answered, double ratio) {
    if (answered == 0) return (label: 'Yeni', color: Colors.white54);
    if (ratio >= 0.85 && answered >= 3) {
      return (label: 'Uzman', color: StudioPalette.emerald);
    }
    if (ratio >= 0.65) return (label: 'Gelişiyor', color: StudioPalette.gold);
    if (ratio >= 0.40) return (label: 'Orta', color: StudioPalette.amber);
    return (label: 'Destek Gerek', color: StudioPalette.crimson);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final accent = ctrl.currentWallpaper.primary;
    final badges = ctrl.badges;
    final unlockedCount = badges.where((b) => b.unlocked).length;
    final activeCatCount = Topic.poolCategories
        .where((t) => (ctrl.categoryAnswered[t.label] ?? 0) > 0)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArenaSceneHeader(
                title: 'İlerleme & Başarımlar',
                description:
                    'Kariyer rütben, 23 alan analizi, $unlockedCount/${badges.length} rozet ve performans grafiklerin',
                scene: _sceneForSection(),
                trailing: LevelMedallion(level: ctrl.level),
              ),
              const SizedBox(height: 11),
              ArenaScrollPills<int>(
                items: const [0, 1, 2, 3],
                selected: _section,
                labelBuilder: (idx) => switch (idx) {
                  0 => 'Genel Bakış',
                  1 => 'Alan Ustalığı ($activeCatCount/${Topic.poolCategories.length})',
                  2 => 'Rozetler ($unlockedCount/${badges.length})',
                  _ => 'Geçmiş (${ctrl.history.length})',
                },
                iconBuilder: (idx) => switch (idx) {
                  0 => Icons.insights_rounded,
                  1 => Icons.radar_rounded,
                  2 => Icons.emoji_events_rounded,
                  _ => Icons.history_rounded,
                },
                onSelected: (idx) => setState(() => _section = idx),
                accent: accent,
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_section) {
            0 => _buildOverviewSection(context, ctrl, accent),
            1 => _buildMasterySection(context, ctrl, accent),
            2 => _buildBadgesSection(context, ctrl, accent),
            _ => _buildHistorySection(context, ctrl, accent),
          },
        ),
      ],
    );
  }

  // =========================================================================
  // BÖLÜM 0: GENEL BAKIŞ (3D KARİYER, KPI, GRAFİK, AKILLI ÖNERİLER, ZİRVE)
  // =========================================================================
  Widget _buildOverviewSection(BuildContext context, ArenaController ctrl, Color accent) {
    final totalAns = ctrl.categoryAnswered.values.fold<int>(0, (a, b) => a + b);
    final totalCor = ctrl.categoryCorrect.values.fold<int>(0, (a, b) => a + b);
    final accPct = totalAns == 0 ? 0 : ((totalCor / totalAns) * 100).round();
    final bestStreak = ctrl.history.fold<int>(0, (acc, h) => max(acc, h.maxStreak));
    final badges = ctrl.badges;
    final unlockedCount = badges.where((b) => b.unlocked).length;
    final rank = _rankForLevel(ctrl.level);
    final xpToNext = 250 - ctrl.xpInCurrentLevel;
    final solvedRatio = ctrl.totalPoolCount == 0
        ? 0.0
        : (ctrl.playedQuestionIds.length / ctrl.totalPoolCount).clamp(0.0, 1.0);

    // En güçlü / en zayıf / keşfedilmemiş alan analizi
    final answeredTopics = <({Topic topic, int ans, int cor, double ratio})>[];
    final unexploredTopics = <Topic>[];
    for (final t in Topic.poolCategories) {
      final ans = ctrl.categoryAnswered[t.label] ?? 0;
      final cor = ctrl.categoryCorrect[t.label] ?? 0;
      if (ans > 0) {
        answeredTopics.add((topic: t, ans: ans, cor: cor, ratio: cor / ans));
      } else {
        unexploredTopics.add(t);
      }
    }
    answeredTopics.sort((a, b) => b.ratio.compareTo(a.ratio));
    final strongest = answeredTopics.isEmpty ? null : answeredTopics.first;
    final weakest = answeredTopics.isEmpty
        ? null
        : (answeredTopics.toList()..sort((a, b) => a.ratio.compareTo(b.ratio))).first;

    final accColor = totalAns == 0
        ? StudioPalette.goldBright
        : (accPct >= 75
            ? StudioPalette.emerald
            : (accPct >= 50 ? StudioPalette.gold : StudioPalette.crimson));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 108),
      children: [
        // 1. 3D Kariyer & Seviye Plaketi
        Studio3DPlaque(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          chamfer: 15,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [StudioPalette.goldBright, StudioPalette.goldDeep],
                      ),
                      boxShadow: [
                        BoxShadow(color: StudioPalette.gold.withValues(alpha: 0.45), blurRadius: 14),
                      ],
                    ),
                    child: Icon(rank.icon, color: StudioPalette.night, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rank.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w900,
                            color: StudioPalette.goldBright,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rank.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Seviye ${ctrl.level} · ${_formatNum(ctrl.xp)} XP',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '+$xpToNext XP kaldı',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Studio3DProgressBar(
                value: (ctrl.xpInCurrentLevel / 250.0).clamp(0.04, 1.0),
                color: StudioPalette.gold,
                endColor: StudioPalette.goldBright,
                height: 8,
              ),
              const SizedBox(height: 11),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [
                  _statusTag(
                    icon: Icons.local_fire_department_rounded,
                    label: '${ctrl.dailyStreak} Günlük Seri',
                    color: StudioPalette.amber,
                  ),
                  InkWell(
                    onTap: ctrl.isDailyChallengeDoneToday ? null : ctrl.startDailyChallenge,
                    borderRadius: BorderRadius.circular(99),
                    child: _statusTag(
                      icon: ctrl.isDailyChallengeDoneToday
                          ? Icons.verified_rounded
                          : Icons.bolt_rounded,
                      label: ctrl.isDailyChallengeDoneToday
                          ? 'Günün Turu Tamam ✓'
                          : 'Günün Turunu Başlat →',
                      color: ctrl.isDailyChallengeDoneToday
                          ? StudioPalette.emerald
                          : StudioPalette.goldBright,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. 2×3 3D Studio KPI Metrik Izgarası
        const Studio3DSectionHeader(
          icon: Icons.analytics_rounded,
          title: 'Performans Karnesi',
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: Studio3DMetricTile(
                icon: Icons.track_changes_rounded,
                value: '%$accPct',
                label: 'Genel Doğruluk',
                sublabel: '$totalCor / $totalAns doğru',
                accent: accColor,
                onTap: () => setState(() => _section = 1),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Studio3DMetricTile(
                icon: Icons.explore_rounded,
                value: _formatNum(ctrl.playedQuestionIds.length),
                label: 'Çözülen Soru',
                sublabel: '%${(solvedRatio * 100).toStringAsFixed(2)} havuz keşfi',
                accent: StudioPalette.sapphire,
                onTap: () => setState(() => _section = 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: Studio3DMetricTile(
                icon: Icons.stairs_rounded,
                value: ctrl.zirveEnIyi > 0 ? puanYaz(ctrl.zirveEnIyi) : '0p',
                label: 'Zirve Rekoru',
                sublabel: 'Basamak ${ctrl.zirveEnUstBasamak} / 15',
                accent: StudioPalette.goldBright,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ZirveScreen(
                      controller: ctrl,
                      konu: ctrl.setup.topic,
                      konular: ctrl.setup.effectiveTopics,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Studio3DMetricTile(
                icon: Icons.emoji_events_rounded,
                value: '$unlockedCount / ${badges.length}',
                label: 'Rozetler',
                sublabel: '%${((unlockedCount / max(1, badges.length)) * 100).round()} tamamlandı',
                accent: const Color(0xFFFFB454),
                onTap: () => setState(() => _section = 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: Studio3DMetricTile(
                icon: Icons.local_fire_department_rounded,
                value: '$bestStreak',
                label: 'En İyi Seri',
                sublabel: '${ctrl.history.length} tamamlanan tur',
                accent: StudioPalette.emerald,
                onTap: () => setState(() => _section = 3),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Studio3DMetricTile(
                icon: Icons.replay_rounded,
                value: '${ctrl.reviewDeck.length}',
                label: 'Tekrar Kartı',
                sublabel: '${ctrl.dueReviewCards.length} şimdi bekliyor',
                accent: const Color(0xFFC5A3FF),
                onTap: ctrl.reviewDeck.isEmpty ? null : ctrl.startSpacedRepetitionReview,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3. Canlı 3D Performans Grafiği (Son Turlar Trendi veya Kategori Sütun Grafiği)
        Studio3DSectionHeader(
          icon: Icons.show_chart_rounded,
          title: ctrl.history.length >= 2
              ? 'Son Turlar Başarı Trendi'
              : 'Alan Doğruluk Grafiği',
          badge: ctrl.history.length >= 2
              ? 'Son ${min(12, ctrl.history.length)} Tur'
              : '${answeredTopics.length} Alan',
        ),
        const SizedBox(height: 9),
        ArenaGlassCard(
          tint: StudioPalette.gold,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: ctrl.history.length >= 2
              ? _buildRoundTrendChart(ctrl.history.take(12).toList().reversed.toList())
              : _buildCategoryChartPreview(answeredTopics),
        ),
        const SizedBox(height: 16),

        // 4. Akıllı Çalışma Analizi & Kişisel Öneriler
        const Studio3DSectionHeader(
          icon: Icons.lightbulb_rounded,
          title: 'Akıllı Çalışma Analizi',
          badge: 'Kişisel',
        ),
        const SizedBox(height: 9),
        ArenaGlassCard(
          tint: StudioPalette.sapphire,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (strongest != null)
                _insightRow(
                  icon: Icons.military_tech_rounded,
                  color: StudioPalette.emerald,
                  title: 'En Güçlü Alanın: ${strongest.topic.label}',
                  subtitle:
                      '${strongest.cor}/${strongest.ans} doğru (%${(strongest.ratio * 100).round()}) ile öne çıkıyorsun.',
                ),
              if (weakest != null && (strongest == null || weakest.topic != strongest.topic || weakest.ratio < 0.8)) ...[
                if (strongest != null) const Divider(color: Colors.white12, height: 18),
                _insightRow(
                  icon: Icons.trending_up_rounded,
                  color: StudioPalette.amber,
                  title: 'Gelişime Açık: ${weakest.topic.label}',
                  subtitle:
                      '${weakest.cor}/${weakest.ans} (%${(weakest.ratio * 100).round()}) — 10 soruluk odak turuyla ustalığını yükselt.',
                ),
                const SizedBox(height: 9),
                Studio3DButton(
                  label: '${weakest.topic.label} · Odak Çalış (10)',
                  icon: Icons.play_arrow_rounded,
                  expand: true,
                  fontSize: 12.8,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  onPressed: () => ctrl.startTopicPractice(weakest.topic),
                ),
              ],
              if (unexploredTopics.isNotEmpty) ...[
                if (strongest != null || weakest != null)
                  const Divider(color: Colors.white12, height: 18),
                _insightRow(
                  icon: Icons.public_rounded,
                  color: StudioPalette.sapphire,
                  title: '${unexploredTopics.length} Yeni Alan Seni Bekliyor',
                  subtitle:
                      'Sıradaki öneri: ${unexploredTopics.first.label} (${_formatNum(ctrl.countForTopic(unexploredTopics.first))} soru).',
                ),
                const SizedBox(height: 9),
                Studio3DButton(
                  label: '${unexploredTopics.first.label} Alanını Keşfet',
                  icon: Icons.explore_rounded,
                  variant: StudioButtonVariant.navy,
                  shimmer: false,
                  expand: true,
                  fontSize: 12.8,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  onPressed: () => ctrl.startTopicPractice(unexploredTopics.first),
                ),
              ],
              if (ctrl.dueReviewCards.isNotEmpty) ...[
                const Divider(color: Colors.white12, height: 18),
                _insightRow(
                  icon: Icons.replay_circle_filled_rounded,
                  color: const Color(0xFFC5A3FF),
                  title: '${ctrl.dueReviewCards.length} Tekrar Kartı Hazır',
                  subtitle: 'Leitner tekrarını şimdi yaparak hafızanı kalıcılaştır.',
                ),
                const SizedBox(height: 9),
                Studio3DButton(
                  label: 'Bekleyen Tekrarı Başlat',
                  icon: Icons.replay_rounded,
                  variant: StudioButtonVariant.emerald,
                  shimmer: false,
                  expand: true,
                  fontSize: 12.8,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  onPressed: ctrl.startSpacedRepetitionReview,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 5. Zirve Merdiveni 15-Basamak Görsel Karnesi
        Studio3DSectionHeader(
          icon: Icons.stairs_rounded,
          title: 'Zirve Merdiveni Karnesi',
          badge: '${ctrl.zirveEnUstBasamak}/15',
        ),
        const SizedBox(height: 9),
        ArenaGlassCard(
          tint: StudioPalette.gold,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ctrl.zirveEnIyi > 0
                              ? 'En Yüksek Ödül: ${puanYaz(ctrl.zirveEnIyi)} puan'
                              : 'Henüz Zirve Rekorun Yok',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: StudioPalette.goldBright,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ulaşılan en yüksek basamak: ${ctrl.zirveEnUstBasamak} · 5. ve 10. basamaklar güvenli barajdır.',
                          style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.74)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 54,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var step = 1; step <= 15; step++) ...[
                      if (step > 1) const SizedBox(width: 3),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: 0.25 + (step / 15.0) * 0.75,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      gradient: step <= ctrl.zirveEnUstBasamak
                                          ? const LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [StudioPalette.goldBright, StudioPalette.goldDeep],
                                            )
                                          : null,
                                      color: step <= ctrl.zirveEnUstBasamak
                                          ? null
                                          : (step == 5 || step == 10 || step == 15)
                                              ? StudioPalette.gold.withValues(alpha: 0.26)
                                              : Colors.white.withValues(alpha: 0.1),
                                      border: (step == 5 || step == 10 || step == 15)
                                          ? Border.all(
                                              color: StudioPalette.goldBright.withValues(alpha: 0.8),
                                              width: 1,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              (step == 5 || step == 10 || step == 15) ? '$step' : '',
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                color: StudioPalette.goldBright,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Studio3DButton(
                label: 'Zirve Merdivenine Çık',
                icon: Icons.stairs_rounded,
                expand: true,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ZirveScreen(
                      controller: ctrl,
                      konu: ctrl.setup.topic,
                      konular: ctrl.setup.effectiveTopics,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 6. Tasarım Defterim (varsa)
        if (ctrl.creationPortfolio.isNotEmpty) ...[
          const SizedBox(height: 14),
          ArenaGlassCard(
            tint: StudioPalette.emerald,
            onTap: () => _openCreationPortfolioSheet(context, ctrl),
            child: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: StudioPalette.goldBright, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tasarım Defterim',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${ctrl.creationPortfolio.length} kayıtlı çalışma',
                        style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: StudioPalette.goldBright),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRoundTrendChart(List<RoundSummary> rounds) {
    final values = rounds.map((r) => r.accuracy.clamp(0.0, 1.0)).toList();
    final avgPct = (values.fold<double>(0, (a, b) => a + b) / values.length * 100).round();
    final peakPct = (values.fold<double>(0, max) * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _chartLegendPill('Ortalama %$avgPct', StudioPalette.goldBright),
            const SizedBox(width: 7),
            _chartLegendPill('Zirve %$peakPct', StudioPalette.emerald),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 132,
          child: CustomPaint(
            painter: _TrendLineChartPainter(values: values),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Eski Tur',
              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.55)),
            ),
            Text(
              'En Son Tur (%${(values.last * 100).round()})',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: StudioPalette.goldBright,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryChartPreview(
    List<({Topic topic, int ans, int cor, double ratio})> answeredTopics,
  ) {
    if (answeredTopics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            const Icon(Icons.auto_graph_rounded, color: StudioPalette.goldBright, size: 32),
            const SizedBox(height: 8),
            const Text(
              'Grafik Verisi Bekleniyor',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              'İlk turunu tamamladığında doğruluk trendin ve alan sütun grafiğin burada canlı olarak çizilir.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.8, color: Colors.white.withValues(alpha: 0.72)),
            ),
          ],
        ),
      );
    }

    final top = answeredTopics.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 118,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < top.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '%${(top[i].ratio * 100).round()}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: top[i].topic.accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: max(0.12, top[i].ratio),
                            widthFactor: 0.68,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(7),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    top[i].topic.accent,
                                    top[i].topic.accent.withValues(alpha: 0.35),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: top[i].topic.accent.withValues(alpha: 0.38),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        top[i].topic.label.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9.8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // BÖLÜM 1: ALAN USTALIĞI (23 KATEGORİ DERİN ANALİZ & HIZLI PRATİK)
  // =========================================================================
  Widget _buildMasterySection(BuildContext context, ArenaController ctrl, Color accent) {
    var expertCount = 0;
    var growingCount = 0;
    var needsWorkCount = 0;
    var unexploredCount = 0;

    final rows = <({Topic topic, int ans, int cor, double ratio})>[];
    for (final t in Topic.poolCategories) {
      final ans = ctrl.categoryAnswered[t.label] ?? 0;
      final cor = ctrl.categoryCorrect[t.label] ?? 0;
      final ratio = ans == 0 ? 0.0 : (cor / ans).clamp(0.0, 1.0);
      if (ans == 0) {
        unexploredCount++;
      } else if (ratio >= 0.85 && ans >= 3) {
        expertCount++;
      } else if (ratio >= 0.50) {
        growingCount++;
      } else {
        needsWorkCount++;
      }
      rows.add((topic: t, ans: ans, cor: cor, ratio: ratio));
    }

    final qLower = _masteryQuery.trim().toLowerCase();
    final filtered = rows.where((r) {
      if (qLower.isNotEmpty && !r.topic.label.toLowerCase().contains(qLower)) return false;
      switch (_masteryFilter) {
        case _MasteryFilter.all:
          return true;
        case _MasteryFilter.active:
          return r.ans > 0;
        case _MasteryFilter.weak:
          return r.ans > 0 && r.ratio < 0.70;
        case _MasteryFilter.unexplored:
          return r.ans == 0;
      }
    }).toList();

    switch (_masterySort) {
      case _MasterySort.accuracyDesc:
        filtered.sort((a, b) {
          if (a.ans == 0 && b.ans > 0) return 1;
          if (b.ans == 0 && a.ans > 0) return -1;
          final c = b.ratio.compareTo(a.ratio);
          return c != 0 ? c : b.ans.compareTo(a.ans);
        });
      case _MasterySort.answeredDesc:
        filtered.sort((a, b) {
          final c = b.ans.compareTo(a.ans);
          return c != 0 ? c : a.topic.label.compareTo(b.topic.label);
        });
      case _MasterySort.weakFirst:
        filtered.sort((a, b) {
          if (a.ans == 0 && b.ans > 0) return 1;
          if (b.ans == 0 && a.ans > 0) return -1;
          final c = a.ratio.compareTo(b.ratio);
          return c != 0 ? c : b.ans.compareTo(a.ans);
        });
      case _MasterySort.alpha:
        filtered.sort((a, b) => a.topic.label.compareTo(b.topic.label));
    }

    final totalCats = max(1, Topic.poolCategories.length);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 108),
      children: [
        // 4-Kademe Ustalık Dağılım Özeti
        ArenaGlassCard(
          tint: StudioPalette.gold,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _tierStat('Uzman', '$expertCount', StudioPalette.emerald)),
                  Expanded(child: _tierStat('Gelişiyor', '$growingCount', StudioPalette.gold)),
                  Expanded(child: _tierStat('Destek', '$needsWorkCount', StudioPalette.crimson)),
                  Expanded(child: _tierStat('Yeni', '$unexploredCount', Colors.white60)),
                ],
              ),
              const SizedBox(height: 10),
              // Segmented mastery bar
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      if (expertCount > 0)
                        Expanded(
                          flex: expertCount,
                          child: const ColoredBox(color: StudioPalette.emerald),
                        ),
                      if (growingCount > 0)
                        Expanded(
                          flex: growingCount,
                          child: const ColoredBox(color: StudioPalette.gold),
                        ),
                      if (needsWorkCount > 0)
                        Expanded(
                          flex: needsWorkCount,
                          child: const ColoredBox(color: StudioPalette.crimson),
                        ),
                      if (unexploredCount > 0)
                        Expanded(
                          flex: unexploredCount,
                          child: ColoredBox(color: Colors.white.withValues(alpha: 0.14)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${totalCats - unexploredCount} / $totalCats alan keşfedildi · Herhangi bir alanda tek dokunuşla 10 soruluk çalışma başlat.',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.72)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Arama + Filtre + Sıralama
        TextField(
          controller: _masterySearchCtrl,
          onChanged: (v) => setState(() => _masteryQuery = v),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Kategori ara (Biyoloji, Fizik, Tarih...)',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 12.5),
            prefixIcon: const Icon(Icons.search_rounded, color: StudioPalette.gold, size: 19),
            suffixIcon: _masteryQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                    onPressed: () => setState(() {
                      _masteryQuery = '';
                      _masterySearchCtrl.clear();
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
        ArenaScrollPills<_MasteryFilter>(
          items: _MasteryFilter.values,
          selected: _masteryFilter,
          labelBuilder: (f) => f.label,
          onSelected: (f) => setState(() => _masteryFilter = f),
          accent: accent,
        ),
        const SizedBox(height: 7),
        ArenaScrollPills<_MasterySort>(
          items: _MasterySort.values,
          selected: _masterySort,
          labelBuilder: (s) => s.label,
          onSelected: (s) => setState(() => _masterySort = s),
          accent: StudioPalette.sapphire,
        ),
        const SizedBox(height: 11),

        if (filtered.isEmpty)
          ArenaGlassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Bu filtreyle eşleşen kategori bulunamadı.',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.72)),
                ),
              ),
            ),
          ),

        for (final r in filtered) _buildMasteryCategoryCard(ctrl, r.topic, r.ans, r.cor, r.ratio),
      ],
    );
  }

  Widget _buildMasteryCategoryCard(
    ArenaController ctrl,
    Topic topic,
    int ans,
    int cor,
    double ratio,
  ) {
    final tier = _tierForTopic(ans, ratio);
    final wrong = max(0, ans - cor);
    final poolSize = ctrl.countForTopic(topic);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ArenaGlassCard(
        tint: topic.accent,
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        topic.detailImage,
                        width: 44,
                        height: 44,
                        cacheWidth: 120,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                      ),
                      Container(
                        width: 44,
                        height: 44,
                        color: StudioPalette.night.withValues(alpha: 0.45),
                      ),
                      Icon(topic.icon, size: 20, color: topic.accent),
                    ],
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              topic.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: tier.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: tier.color.withValues(alpha: 0.55)),
                            ),
                            child: Text(
                              tier.label,
                              style: TextStyle(
                                fontSize: 9.8,
                                fontWeight: FontWeight.w900,
                                color: tier.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ans == 0
                            ? 'Henüz çözülmedi · ${_formatNum(poolSize)} soru hazır'
                            : '$cor doğru · $wrong yanlış · %${(ratio * 100).round()} · ${_formatNum(poolSize)} soru',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.2,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Studio3DProgressBar(
                    value: ans == 0 ? 0.02 : ratio,
                    color: topic.accent,
                    height: 7,
                  ),
                ),
                const SizedBox(width: 10),
                Studio3DButton(
                  label: 'Çalış',
                  icon: Icons.play_arrow_rounded,
                  variant: ans == 0 ? StudioButtonVariant.navy : StudioButtonVariant.gold,
                  shimmer: false,
                  fontSize: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
                  onPressed: () => ctrl.startTopicPractice(topic),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // BÖLÜM 2: ROZETLER (16 ADET 3D BAŞARIM & KUPA ODASI)
  // =========================================================================
  Widget _buildBadgesSection(BuildContext context, ArenaController ctrl, Color accent) {
    final allBadges = ctrl.badges;
    final unlockedCount = allBadges.where((b) => b.unlocked).length;
    final pct = allBadges.isEmpty ? 0.0 : unlockedCount / allBadges.length;

    final filtered = allBadges.where((b) {
      return switch (_badgeFilter) {
        _BadgeFilter.all => true,
        _BadgeFilter.unlocked => b.unlocked,
        _BadgeFilter.locked => !b.unlocked,
        _BadgeFilter.akademi => b.group == 'Akademi',
        _BadgeFilter.ustalik => b.group == 'Ustalık',
        _BadgeFilter.zirve => b.group == 'Zirve',
      };
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 108),
      children: [
        Studio3DPlaque(
          padding: const EdgeInsets.all(15),
          chamfer: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: StudioPalette.goldBright, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$unlockedCount / ${allBadges.length} Rozet Kazanıldı',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: StudioPalette.goldBright,
                      ),
                    ),
                  ),
                  Text(
                    '%${(pct * 100).round()}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Studio3DProgressBar(value: max(0.03, pct), height: 8),
              const SizedBox(height: 6),
              Text(
                'Her rozete dokunarak ayrıntılı hedefine ve ilerleme durumuna bakabilirsin.',
                style: TextStyle(fontSize: 11.2, color: Colors.white.withValues(alpha: 0.74)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ArenaScrollPills<_BadgeFilter>(
          items: _BadgeFilter.values,
          selected: _badgeFilter,
          labelBuilder: (f) => f.label,
          onSelected: (f) => setState(() => _badgeFilter = f),
          accent: accent,
        ),
        const SizedBox(height: 11),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.18,
          ),
          itemBuilder: (ctx, i) => _buildBadgeTile(context, filtered[i]),
        ),
      ],
    );
  }

  Widget _buildBadgeTile(BuildContext context, ArenaBadgeInfo b) {
    final color = b.unlocked ? StudioPalette.gold : Colors.white38;
    return ArenaGlassCard(
      tint: b.unlocked ? StudioPalette.gold : StudioPalette.sapphire,
      padding: const EdgeInsets.all(12),
      onTap: () => _showBadgeDetailDialog(context, b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: b.unlocked
                      ? const LinearGradient(
                          colors: [StudioPalette.goldBright, StudioPalette.goldDeep],
                        )
                      : null,
                  color: b.unlocked ? null : Colors.white.withValues(alpha: 0.08),
                  border: Border.all(color: color.withValues(alpha: 0.7)),
                ),
                child: Icon(
                  _badgeIcon(b.iconKind),
                  size: 16,
                  color: b.unlocked ? StudioPalette.night : Colors.white54,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  b.group.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: b.unlocked ? StudioPalette.goldBright : Colors.white38,
                  ),
                ),
              ),
              if (b.unlocked)
                const Icon(Icons.verified_rounded, size: 16, color: StudioPalette.goldBright)
              else
                const Icon(Icons.lock_outline_rounded, size: 14, color: Colors.white38),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            b.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: b.unlocked ? StudioPalette.goldBright : Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            b.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.2,
              color: Colors.white.withValues(alpha: b.unlocked ? 0.8 : 0.55),
              height: 1.25,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Studio3DProgressBar(
                  value: b.progress,
                  color: b.unlocked ? StudioPalette.emerald : StudioPalette.gold,
                  height: 5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${b.current}/${b.target}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: b.unlocked ? const Color(0xFF7AF0A8) : Colors.white60,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showBadgeDetailDialog(BuildContext context, ArenaBadgeInfo b) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioPalette.navyMid,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Studio3DOrbitEmblem(
              icon: _badgeIcon(b.iconKind),
              size: 68,
              accent: b.unlocked ? StudioPalette.gold : StudioPalette.sapphire,
            ),
            const SizedBox(height: 12),
            Text(
              b.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: StudioPalette.goldBright,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              b.description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            Studio3DProgressBar(
              value: b.progress,
              color: b.unlocked ? StudioPalette.emerald : StudioPalette.gold,
              height: 8,
            ),
            const SizedBox(height: 6),
            Text(
              b.unlocked
                  ? 'Başarım Açıldı! (${b.current}/${b.target})'
                  : 'İlerleme: ${b.current} / ${b.target}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: b.unlocked ? const Color(0xFF7AF0A8) : StudioPalette.goldBright,
              ),
            ),
          ],
        ),
        actions: [
          Studio3DButton(
            label: 'Tamam',
            shimmer: false,
            fontSize: 13,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // BÖLÜM 3: GEÇMİŞ (TUR GEÇMİŞİ, FİLTRELER & DETAYLI KARNE)
  // =========================================================================
  Widget _buildHistorySection(BuildContext context, ArenaController ctrl, Color accent) {
    final all = ctrl.history;
    final filtered = all.where((h) {
      return switch (_historyFilter) {
        _HistoryFilter.all => true,
        _HistoryFilter.classic => h.mode == GameMode.classic && !h.wasLiveVoice && h.duelStandings.isEmpty,
        _HistoryFilter.training => h.mode == GameMode.training,
        _HistoryFilter.sprint => h.mode == GameMode.sprint,
        _HistoryFilter.stages => h.mode == GameMode.stages,
        _HistoryFilter.voice => h.wasLiveVoice,
        _HistoryFilter.duel => h.duelStandings.isNotEmpty,
      };
    }).toList();

    final avgAcc = all.isEmpty
        ? 0
        : (all.fold<double>(0, (acc, h) => acc + h.accuracy) / all.length * 100).round();
    final maxScore = all.fold<int>(0, (acc, h) => max(acc, h.totalScore));
    final totalXpFromHistory = all.fold<int>(0, (acc, h) => acc + h.xpGained);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 108),
      children: [
        ArenaGlassCard(
          tint: StudioPalette.gold,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(child: _tierStat('Tur', '${all.length}', StudioPalette.goldBright)),
              Expanded(child: _tierStat('Ort. Başarı', '%$avgAcc', StudioPalette.emerald)),
              Expanded(child: _tierStat('Rekor Puan', '${_formatNum(maxScore)}p', StudioPalette.sapphire)),
              Expanded(child: _tierStat('Toplam XP', '+${_formatNum(totalXpFromHistory)}', const Color(0xFFFFB454))),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ArenaScrollPills<_HistoryFilter>(
          items: _HistoryFilter.values,
          selected: _historyFilter,
          labelBuilder: (f) => f.label,
          onSelected: (f) => setState(() => _historyFilter = f),
          accent: accent,
        ),
        const SizedBox(height: 10),

        if (all.isEmpty)
          ArenaGlassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 14),
              child: Column(
                children: [
                  const Icon(Icons.history_toggle_off_rounded,
                      color: StudioPalette.goldBright, size: 34),
                  const SizedBox(height: 10),
                  const Text(
                    'Henüz tamamlanmış bir tur yok',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'İlk turunu Oyna sekmesinden veya hemen aşağıdan başlatabilirsin!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.2, color: Colors.white.withValues(alpha: 0.72)),
                  ),
                  const SizedBox(height: 14),
                  Studio3DButton(
                    label: 'Hızlı Karma Tur Başlat (10)',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => ctrl.startTopicPractice(Topic.mixed),
                  ),
                ],
              ),
            ),
          )
        else if (filtered.isEmpty)
          ArenaGlassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Seçili modda kayıtlı tur bulunamadı.',
                  style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.72)),
                ),
              ),
            ),
          ),

        for (final h in filtered.take(30)) _buildHistoryCard(ctrl, h),
      ],
    );
  }

  Widget _buildHistoryCard(ArenaController ctrl, RoundSummary h) {
    final expanded = _expandedHistoryIds.contains(h.id);
    final pct = (h.accuracy * 100).round();
    final accColor = pct >= 80
        ? StudioPalette.emerald
        : (pct >= 50 ? StudioPalette.gold : StudioPalette.crimson);
    const months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    final dateStr =
        '${h.playedAt.day} ${months[(h.playedAt.month - 1).clamp(0, 11)]} · ${h.playedAt.hour.toString().padLeft(2, '0')}:${h.playedAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ArenaGlassCard(
        tint: h.topic.accent,
        padding: const EdgeInsets.all(13),
        onTap: () => setState(() {
          if (!_expandedHistoryIds.remove(h.id)) {
            _expandedHistoryIds.add(h.id);
          }
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: h.topic.accent.withValues(alpha: 0.2),
                  child: Icon(h.topic.icon, color: h.topic.accent, size: 19),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$dateStr · ${h.mode.label}${h.wasLiveVoice ? " · Sesli" : ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.65)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accColor.withValues(alpha: 0.65)),
                  ),
                  child: Text(
                    '%$pct',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: accColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${h.correctCount}/${h.totalQuestions} doğru · +${h.xpGained} XP · Seri ${h.maxStreak}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_formatNum(h.totalScore)}p',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: StudioPalette.goldBright,
                  ),
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 10),
              Studio3DProgressBar(value: h.accuracy, color: accColor, height: 6),
              if (h.duelStandings.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Düello Sıralaması:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: StudioPalette.goldBright,
                  ),
                ),
                const SizedBox(height: 4),
                for (var i = 0; i < h.duelStandings.length; i++)
                  Text(
                    '${i + 1}. ${h.duelStandings[i]['name']} — ${h.duelStandings[i]['score']}p (${h.duelStandings[i]['correct']} doğru)',
                    style: const TextStyle(fontSize: 11.8, color: Colors.white70),
                  ),
              ],
              const SizedBox(height: 10),
              Studio3DButton(
                label: '${h.topic.label} · Tekrar Oyna',
                icon: Icons.replay_rounded,
                shimmer: false,
                expand: true,
                fontSize: 12.5,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                onPressed: () => ctrl.startTopicPractice(
                  h.topic,
                  count: max(5, min(20, h.totalQuestions)),
                  mode: h.mode,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openCreationPortfolioSheet(BuildContext context, ArenaController ctrl) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final entries = ctrl.creationPortfolio.entries.toList().reversed.toList();
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.8,
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final q = ctrl.questionById(entry.key);
                return ExpansionTile(
                  title: Text(q?.lesson ?? 'Kayıtlı tasarım'),
                  subtitle: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                  childrenPadding: const EdgeInsets.all(16),
                  children: [
                    if (q?.creation != null) Text(q!.creation!.brief),
                    if (q?.visual != null)
                      QuestionVisualViewer(visual: q!.visual!, accent: q.category.accent),
                    const SizedBox(height: 8),
                    SelectableText(entry.value),
                    for (final criterion in q?.creation?.criteria ?? const <String>[])
                      Align(alignment: Alignment.centerLeft, child: Text('• $criterion')),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // =========================================================================
  // ORTAK KÜÇÜK YARDIMCILAR
  // =========================================================================
  Widget _statusTag({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _chartLegendPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _tierStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.7)),
        ),
      ],
    );
  }

  Widget _insightRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.8,
                  color: Colors.white.withValues(alpha: 0.76),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _badgeIcon(IconDataCompat kind) {
    switch (kind) {
      case IconDataCompat.spark:
        return Icons.rocket_launch_rounded;
      case IconDataCompat.curious:
        return Icons.explore_rounded;
      case IconDataCompat.hunter:
        return Icons.track_changes_rounded;
      case IconDataCompat.encyclopedia:
        return Icons.menu_book_rounded;
      case IconDataCompat.flawless:
        return Icons.verified_rounded;
      case IconDataCompat.streak:
        return Icons.local_fire_department_rounded;
      case IconDataCompat.master:
        return Icons.workspace_premium_rounded;
      case IconDataCompat.sage:
        return Icons.auto_awesome_rounded;
      case IconDataCompat.explorer5:
        return Icons.category_rounded;
      case IconDataCompat.explorer23:
        return Icons.public_rounded;
      case IconDataCompat.zirveMid:
        return Icons.stairs_rounded;
      case IconDataCompat.zirveTop:
        return Icons.emoji_events_rounded;
      case IconDataCompat.collector:
        return Icons.bookmarks_rounded;
      case IconDataCompat.dailyHabit:
        return Icons.calendar_today_rounded;
      case IconDataCompat.voiceStar:
        return Icons.mic_rounded;
      case IconDataCompat.duelKing:
        return Icons.shield_rounded;
    }
  }
}

/// Son turlardaki doğruluk oranını altın parıltılı alan + çizgi grafiği olarak çizer.
class _TrendLineChartPainter extends CustomPainter {
  final List<double> values;
  const _TrendLineChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const padTop = 10.0;
    const padBottom = 10.0;
    const padX = 8.0;
    final usableH = max(1.0, size.height - padTop - padBottom);
    final usableW = max(1.0, size.width - padX * 2);

    // Yatay kılavuz çizgileri (%0, %50, %100)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1.0;
    for (final frac in const [0.0, 0.5, 1.0]) {
      final y = padTop + usableH * (1.0 - frac);
      canvas.drawLine(Offset(padX, y), Offset(size.width - padX, y), gridPaint);
    }

    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : padX + (i / (values.length - 1)) * usableW;
      final y = padTop + usableH * (1.0 - values[i].clamp(0.0, 1.0));
      pts.add(Offset(x, y));
    }

    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final areaPath = Path.from(linePath)
      ..lineTo(pts.last.dx, padTop + usableH)
      ..lineTo(pts.first.dx, padTop + usableH)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            StudioPalette.gold.withValues(alpha: 0.34),
            StudioPalette.gold.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, padTop, size.width, usableH)),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [StudioPalette.gold, StudioPalette.goldBright, StudioPalette.emerald],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    for (var i = 0; i < pts.length; i++) {
      final isLast = i == pts.length - 1;
      canvas.drawCircle(
        pts[i],
        isLast ? 5.2 : 3.4,
        Paint()..color = isLast ? StudioPalette.goldBright : StudioPalette.gold,
      );
      canvas.drawCircle(
        pts[i],
        isLast ? 2.4 : 1.5,
        Paint()..color = StudioPalette.night,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLineChartPainter old) => old.values != values;
}
