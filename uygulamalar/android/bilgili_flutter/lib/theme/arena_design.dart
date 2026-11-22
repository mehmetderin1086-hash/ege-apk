import 'dart:math';
import 'package:flutter/material.dart';

class ArenaWallpaper {
  final String id;
  final String title;
  final String subtitle;
  final String? assetPath;
  final Color primary;
  final Color secondary;
  final Color surface;
  final Color ink;
  /// Resimsiz temalarda arka plan geçişi (yukarıdan aşağı).
  final List<Color>? gradient;

  const ArenaWallpaper({
    required this.id,
    required this.title,
    required this.subtitle,
    this.assetPath,
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.ink,
    this.gradient,
  });
}

enum WallpaperClarity {
  subtle('Hafif', 0.24),
  balanced('Dengeli', 0.40),
  vivid('Canlı', 0.56),
  crisp('Tam Net', 0.72);

  final String label;
  final double opacity;
  const WallpaperClarity(this.label, this.opacity);
}

enum EffectIntensity {
  off('Kapalı', 0.0),
  subtle('Zarif', 0.55),
  rich('Zengin', 1.0);

  final String label;
  final double factor;
  const EffectIntensity(this.label, this.factor);
}

class ArenaWallpapers {
  static const List<ArenaWallpaper> catalog = [
    ArenaWallpaper(
      id: 'studyo',
      title: 'Gece Stüdyosu',
      subtitle: 'Lacivert sahne ışıkları, altın vurgular',
      primary: Color(0xFFF2C14E),
      secondary: Color(0xFF5AA9FF),
      surface: Color(0xFF14207A),
      ink: Color(0xFF03061C),
      gradient: [Color(0xFF1C2C8C), Color(0xFF0B1450), Color(0xFF060A2E), Color(0xFF03061C)],
    ),
    ArenaWallpaper(
      id: 'lavanta',
      title: 'Lavanta',
      subtitle: 'Parlak mor geçiş, yeşil vurgular',
      primary: Color(0xFF8DD14F),
      secondary: Color(0xFFFFB03A),
      surface: Color(0xFF3B1FA3),
      ink: Color(0xFF1E0D5E),
      gradient: [Color(0xFF7356E8), Color(0xFF5B34DC), Color(0xFF3A1A9E), Color(0xFF200F62)],
    ),
    ArenaWallpaper(
      id: 'observatory',
      title: 'Gök Kubbe',
      subtitle: 'Yıldızlı rasathane ve altın usturlap',
      assetPath: 'assets/images/scene_observatory.webp',
      primary: Color(0xFF4CE0D2),
      secondary: Color(0xFFF6C453),
      surface: Color(0xFF0E1B33),
      ink: Color(0xFF060C1A),
    ),
    ArenaWallpaper(
      id: 'academy',
      title: 'Altın Akademi',
      subtitle: 'Klasik kubbeli bilgelik salonu',
      assetPath: 'assets/images/scene_academy.webp',
      primary: Color(0xFFF6C453),
      secondary: Color(0xFF5AD8C6),
      surface: Color(0xFF1D1814),
      ink: Color(0xFF0E0B09),
    ),
    ArenaWallpaper(
      id: 'atrium',
      title: 'Zümrüt Sera',
      subtitle: 'Biyolüminesan botanik bilim kubbesi',
      assetPath: 'assets/images/scene_atrium.webp',
      primary: Color(0xFF5CE09B),
      secondary: Color(0xFF4CE0D2),
      surface: Color(0xFF0B221E),
      ink: Color(0xFF05110F),
    ),
    ArenaWallpaper(
      id: 'cyber_arena',
      title: 'Siber Arena',
      subtitle: 'Holografik yarışma sahnesi',
      assetPath: 'assets/images/scene_cyber_arena.webp',
      primary: Color(0xFF58D5E3),
      secondary: Color(0xFFB88CFF),
      surface: Color(0xFF13122B),
      ink: Color(0xFF080716),
    ),
    ArenaWallpaper(
      id: 'duel_stage',
      title: 'Şampiyon Sahnesi',
      subtitle: 'Turnuva kalkanları ve zafer ışıkları',
      assetPath: 'assets/images/scene_duel_stage.webp',
      primary: Color(0xFFFFB454),
      secondary: Color(0xFF63B3FF),
      surface: Color(0xFF1A1528),
      ink: Color(0xFF0A0812),
    ),
    ArenaWallpaper(
      id: 'study_book', title: 'Okuma Masası', subtitle: 'Açık kitap ve altın ışık',
      assetPath: 'assets/images/study_book.webp', primary: Color(0xff83d7cc), secondary: Color(0xffe5b868),
      surface: Color(0xff192422), ink: Color(0xff0c1415),
    ),
    ArenaWallpaper(
      id: 'study_pen', title: 'Mürekkep Atölyesi', subtitle: 'Dolma kalem ve kâğıt dokusu',
      assetPath: 'assets/images/study_pen.webp', primary: Color(0xff97d6ef), secondary: Color(0xffe7bf7c),
      surface: Color(0xff152537), ink: Color(0xff081322),
    ),
    ArenaWallpaper(
      id: 'pure_night',
      title: 'Saf Gece',
      subtitle: 'Odaklı okuma için dingin lacivert',
      assetPath: null,
      primary: Color(0xFF4CE0D2),
      secondary: Color(0xFF68A8FF),
      surface: Color(0xFF0E182B),
      ink: Color(0xFF060B16),
    ),
  ];

  static ArenaWallpaper byId(String id) {
    return catalog.firstWhere((w) => w.id == id, orElse: () => catalog.first);
  }
}

class ArenaAmbientBackground extends StatefulWidget {
  final ArenaWallpaper wallpaper;
  final WallpaperClarity clarity;
  final EffectIntensity intensity;
  final bool reduceMotion;
  final Widget child;

  const ArenaAmbientBackground({
    super.key,
    required this.wallpaper,
    required this.clarity,
    required this.intensity,
    this.reduceMotion = false,
    required this.child,
  });

  @override
  State<ArenaAmbientBackground> createState() => _ArenaAmbientBackgroundState();
}

class _ArenaAmbientBackgroundState extends State<ArenaAmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ArenaAmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion ||
        oldWidget.intensity != widget.intensity) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.reduceMotion || MediaQuery.disableAnimationsOf(context) || widget.intensity == EffectIntensity.off) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wp = widget.wallpaper;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (wp.gradient != null)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomCenter, colors: wp.gradient!),
            ),
          )
        else
          ColoredBox(color: wp.ink),
        if (wp.assetPath != null)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, img) {
              final scale = (widget.reduceMotion || widget.intensity == EffectIntensity.off)
                  ? 1.0
                  : 1.055 + 0.018 * sin(_ctrl.value * 2 * pi);
              final drift = scale == 1.0 ? Offset.zero : Offset(
                4 * sin(_ctrl.value * 2 * pi), 5 * cos(_ctrl.value * 2 * pi));
              return Transform.translate(offset: drift, child: Transform.scale(scale: scale, child: img));
            },
            child: Opacity(
              opacity: min(1.0, widget.clarity.opacity + .22),
              child: Image.asset(
                wp.assetPath!,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        if (wp.gradient == null) DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                wp.ink.withValues(alpha: 0.12),
                wp.surface.withValues(alpha: 0.38),
                wp.ink.withValues(alpha: 0.76),
              ],
            ),
          ),
        ),
        if (widget.intensity != EffectIntensity.off)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => CustomPaint(
                painter: _ArenaAtmospherePainter(
                  progress: _ctrl.value,
                  primary: wp.primary,
                  secondary: wp.secondary,
                  factor: widget.intensity.factor,
                ),
              ),
            ),
          ),
        widget.child,
      ],
    );
  }
}

class _ArenaAtmospherePainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final double factor;

  _ArenaAtmospherePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.factor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * pi;

    // Soft aurora glow orbs
    final orb1 = Offset(
      size.width * (0.2 + 0.12 * sin(t)),
      size.height * (0.14 + 0.05 * cos(t)),
    );
    final orb2 = Offset(
      size.width * (0.82 - 0.10 * cos(t * 0.8)),
      size.height * (0.48 + 0.06 * sin(t * 0.9)),
    );
    canvas.drawCircle(
      orb1,
      size.width * 0.52,
      Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: 0.13 * factor),
            primary.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: orb1, radius: size.width * 0.52)),
    );
    canvas.drawCircle(
      orb2,
      size.width * 0.48,
      Paint()
        ..shader = RadialGradient(
          colors: [
            secondary.withValues(alpha: 0.11 * factor),
            secondary.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: orb2, radius: size.width * 0.48)),
    );

    // Subtle celestial knowledge arc in upper sky
    final arcCenter = Offset(size.width * 0.86, size.height * 0.12);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = primary.withValues(alpha: 0.12 * factor);
    for (var i = 0; i < 2; i++) {
      final r = 74.0 + i * 34.0;
      canvas.drawCircle(arcCenter, r, ringPaint);
      final dotAngle = t * (i == 0 ? 1.0 : -0.7) + i * 1.9;
      final dotPos = Offset(
        arcCenter.dx + cos(dotAngle) * r,
        arcCenter.dy + sin(dotAngle) * r,
      );
      canvas.drawCircle(
        dotPos,
        3.0,
        Paint()..color = (i == 0 ? primary : secondary).withValues(alpha: 0.55 * factor),
      );
    }

    // Floating twinkling constellation motes
    for (var i = 0; i < 18; i++) {
      final baseX = ((i * 61 + 19) % 100) / 100.0 * size.width;
      final baseY = ((i * 43 + 11) % 100) / 100.0 * size.height;
      final driftY = (baseY - progress * 55 * (1 + (i % 3) * 0.35)) % size.height;
      final twinkle = (0.25 + 0.75 * (0.5 + 0.5 * sin(t * 2 + i * 1.3))) * factor;
      final color = i.isEven ? Colors.white : (i % 3 == 0 ? secondary : primary);
      canvas.drawCircle(
        Offset(baseX, driftY < 0 ? driftY + size.height : driftY),
        i % 4 == 0 ? 2.1 : 1.3,
        Paint()..color = color.withValues(alpha: 0.28 * twinkle),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArenaAtmospherePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.primary != primary ||
      oldDelegate.factor != factor;
}

class ArenaGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final double radius;
  final bool highContrast;
  final VoidCallback? onTap;

  const ArenaGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.tint,
    this.radius = 22,
    this.highContrast = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = tint ?? const Color(0xFF4CE0D2);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highContrast
              ? [const Color(0xF20D1526), const Color(0xF5070B14)]
              : [
                  Color.alphaBlend(accent.withValues(alpha: .16), const Color(0xF0192331)),
                  const Color(0xE40A1422),
                ],
        ),
        border: Border.all(
          color: highContrast
              ? accent.withValues(alpha: 0.65)
              : accent.withValues(alpha: 0.24),
          width: highContrast ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(color: Color.lerp(accent, Colors.black, .82)!, offset: const Offset(0, 3)),

          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return ArenaPressDepth(child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: box,
      ),
    ));
  }
}

class ArenaImageActionButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? badge;
  final IconData icon;
  final String imageAsset;
  final Color accent;
  final VoidCallback onTap;
  final double height;

  const ArenaImageActionButton({
    super.key,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.icon,
    required this.imageAsset,
    required this.accent,
    required this.onTap,
    this.height = 114,
  });

  @override
  Widget build(BuildContext context) {
    return ArenaPressDepth(child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.42), width: 1.1),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  imageAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: accent.withValues(alpha: 0.18),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0x66060B16),
                        const Color(0xCC070E1D),
                        const Color(0xF0060B16),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: accent.withValues(alpha: 0.5)),
                            ),
                            child: Icon(icon, size: 16, color: accent),
                          ),
                          const Spacer(),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.52),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: accent.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                badge!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: accent,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class ArenaScrollPills<T> extends StatelessWidget {
  final List<T> items;
  final T selected;
  final String Function(T) labelBuilder;
  final IconData? Function(T)? iconBuilder;
  final ValueChanged<T> onSelected;
  final Color accent;

  const ArenaScrollPills({
    super.key,
    required this.items,
    required this.selected,
    required this.labelBuilder,
    this.iconBuilder,
    required this.onSelected,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _buildPill(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildPill(T item) {
    final isSel = item == selected;
    final icon = iconBuilder?.call(item);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(item),
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: isSel ? [Color.lerp(accent, Colors.white, .34)!, accent] : [const Color(0xff283749), const Color(0xff111b2a)]),
            border: Border.all(
              color: isSel ? accent : Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: isSel ? const Color(0xFF06101F) : accent,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                labelBuilder(item),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                  color: isSel ? const Color(0xFF06101F) : Colors.white.withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LevelMedallion extends StatelessWidget {
  final int level;
  final Color gold;

  const LevelMedallion({
    super.key,
    required this.level,
    this.gold = const Color(0xFFF6C453),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gold.withValues(alpha: 0.28), gold.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: gold.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 10, color: gold),
          Text(
            '$level',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: gold,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

class CountdownRing extends StatelessWidget {
  final int remainingSeconds;
  final int totalSeconds;
  final Color accent;

  const CountdownRing({
    super.key,
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (totalSeconds <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.all_inclusive_rounded, size: 15, color: accent),
            const SizedBox(width: 5),
            Text(
              'Süresiz',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
            ),
          ],
        ),
      );
    }
    final ratio = (remainingSeconds / totalSeconds).clamp(0.0, 1.0);
    final urgent = remainingSeconds <= 4;
    final color = urgent ? const Color(0xFFFF6B7A) : accent;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: ratio,
            strokeWidth: 3.6,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Text(
            '$remainingSeconds',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: urgent ? const Color(0xFFFF8591) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class ConfettiCelebrationOverlay extends StatefulWidget {
  final bool active;
  const ConfettiCelebrationOverlay({super.key, required this.active});

  @override
  State<ConfettiCelebrationOverlay> createState() => _ConfettiCelebrationOverlayState();
}

class _ConfettiCelebrationOverlayState extends State<ConfettiCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant ConfettiCelebrationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.value >= 0.99) return const SizedBox.shrink();
          return CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(_controller.value),
          );
        },
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  _ConfettiPainter(this.t);

  static const _colors = [
    Color(0xFF4CE0D2),
    Color(0xFFF6C453),
    Color(0xFF5AB2FF),
    Color(0xFFFF7BAC),
    Color(0xFF5CE09B),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final fade = (1.0 - t).clamp(0.0, 1.0);
    for (var i = 0; i < 42; i++) {
      final seedX = ((i * 73 + 17) % 100) / 100.0;
      final speed = 0.55 + (i % 5) * 0.16;
      final sway = sin(t * 8 + i) * 18;
      final x = seedX * size.width + sway;
      final y = -20 + t * size.height * speed * 1.15;
      final paint = Paint()
        ..color = _colors[i % _colors.length].withValues(alpha: fade * 0.9);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 6 + i * 0.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-4, -2.5, 8, 5),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}

class ArenaPressDepth extends StatefulWidget {
  final Widget child;
  const ArenaPressDepth({super.key, required this.child});
  @override
  State<ArenaPressDepth> createState() => _ArenaPressDepthState();
}

class _ArenaPressDepthState extends State<ArenaPressDepth> {
  Offset? origin;
  double tilt = 0;
  void reset() { if (origin != null) setState(() {origin = null; tilt = 0;}); }
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return Listener(
      onPointerDown: (event) => setState(() {
        origin = event.position;
        final width = context.size?.width ?? 1;
        tilt = (event.localPosition.dx / max(1, width) - .5).clamp(-.5,.5) * .06;
      }),
      onPointerMove: (event) {if (origin != null && (event.position-origin!).distance > 12) reset();},
      onPointerUp: (_) => reset(), onPointerCancel: (_) => reset(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 115), curve: Curves.easeOut,
        transformAlignment: Alignment.center,
        transform: Matrix4.identity()..setEntry(3,2,.0015)..rotateY(tilt)
          ..scaleByDouble(origin == null ? 1 : .975, origin == null ? 1 : .975, 1, 1),
        child: widget.child,
      ),
    );
  }
}

class ArenaSceneHeader extends StatelessWidget {
  final String title, description, scene;
  const ArenaSceneHeader({super.key, required this.title, required this.description, required this.scene});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: BorderRadius.circular(20), child: Stack(children: [
      Positioned.fill(child: Image.asset(scene == 'notebook' ? 'assets/images/study_pen.webp' : 'assets/images/scene_$scene.webp', fit:BoxFit.cover,
        alignment:const Alignment(0,-.48), excludeFromSemantics:true)),
      Positioned.fill(child: DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(
        begin:Alignment.centerLeft,end:Alignment.centerRight,
        colors:[Color(0xf0070d19),Color(0xb7070d19),Color(0x46070d19)])))),
      Padding(padding:const EdgeInsets.fromLTRB(16,20,26,16),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(title,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w900,color:Colors.white)),
          const SizedBox(height:6),Text(description,style:const TextStyle(fontSize:12,color:Color(0xffe1e8ed))),
        ])),
    ]));
  }
}
