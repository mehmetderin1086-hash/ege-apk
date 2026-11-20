import 'package:flutter/material.dart';
import '../models/quiz_models.dart';
import '../state/arena_controller.dart';
import '../theme/arena_design.dart';

class ProgressTab extends StatelessWidget {
  final ArenaController controller;
  const ProgressTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final wp = controller.currentWallpaper;
    final accent = wp.primary;
    final totalAns = controller.categoryAnswered.values.fold<int>(0, (a, b) => a + b);
    final totalCor = controller.categoryCorrect.values.fold<int>(0, (a, b) => a + b);
    final accPct = totalAns == 0 ? 0 : ((totalCor / totalAns) * 100).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        ArenaSceneHeader(title: 'İlerleme & Başarımlar', description: 'Seviye yolculuğun, konu ustalığın, rozetlerin ve tur geçmişin', scene: 'duel_stage'),
        const SizedBox(height: 14),

        // Overview Hero
        ArenaGlassCard(
          tint: accent,
          child: Row(
            children: [
              LevelMedallion(level: controller.level, gold: wp.secondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seviye ${controller.level} · Toplam ${controller.xp} XP',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalAns yanıt · %$accPct doğruluk · ${controller.history.length} tamamlanan tur',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.72)),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: (controller.xpInCurrentLevel / 250.0).clamp(0.04, 1.0),
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Badges Grid
        const Text(
          'Kazanılan Rozetler',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: controller.badges.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 1.55,
          ),
          itemBuilder: (ctx, i) {
            final b = controller.badges[i];
            final color = b.unlocked ? wp.secondary : Colors.white38;
            return ArenaGlassCard(
              tint: color,
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: color.withValues(alpha: b.unlocked ? 0.22 : 0.08),
                        child: Icon(_badgeIcon(b.iconKind), size: 15, color: color),
                      ),
                      const Spacer(),
                      if (b.unlocked)
                        Icon(Icons.check_circle_rounded, size: 15, color: color),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    b.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: b.unlocked ? Colors.white : Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    b.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: b.unlocked ? 0.74 : 0.44),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 18),

        // Category Mastery
        const Text(
          'Alan Ustalığı',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 10),
        ArenaGlassCard(
          child: Column(
            children: [
              for (final t in Topic.poolCategories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildCategoryBar(t),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Round History
        const Text(
          'Son Turlar',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 10),
        if (controller.history.isEmpty)
          ArenaGlassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Henüz tamamlanmış bir tur yok. İlk turunu Oyna sekmesinden başlat!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.7)),
                ),
              ),
            ),
          ),
        for (final h in controller.history.take(20))
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: ArenaGlassCard(
              tint: h.topic.accent,
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: h.topic.accent.withValues(alpha: 0.18),
                    child: Icon(h.topic.icon, color: h.topic.accent, size: 18),
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
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${h.correctCount}/${h.totalQuestions} doğru · +${h.xpGained} XP · Seri ${h.maxStreak}',
                          style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${h.totalScore}p',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryBar(Topic topic) {
    final ans = controller.categoryAnswered[topic.label] ?? 0;
    final cor = controller.categoryCorrect[topic.label] ?? 0;
    final ratio = ans == 0 ? 0.0 : (cor / ans).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(topic.icon, size: 15, color: topic.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                topic.label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Text(
              ans == 0 ? 'Henüz çözülmedi' : '$cor/$ans (%${(ratio * 100).round()})',
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: ans == 0 ? 0.02 : ratio,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(topic.accent),
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
      case IconDataCompat.flawless:
        return Icons.verified_rounded;
      case IconDataCompat.master:
        return Icons.workspace_premium_rounded;
      case IconDataCompat.collector:
        return Icons.bookmarks_rounded;
      case IconDataCompat.aiExplorer:
        return Icons.hub_rounded;
      case IconDataCompat.voiceStar:
        return Icons.mic_rounded;
      case IconDataCompat.duelKing:
        return Icons.shield_rounded;
    }
  }
}
