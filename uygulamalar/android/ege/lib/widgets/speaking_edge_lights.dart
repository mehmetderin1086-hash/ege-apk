import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Exists only while Ege is speaking; listening never runs this animation.
class SpeakingEdgeLights extends StatefulWidget {
  const SpeakingEdgeLights({super.key});
  @override
  State<SpeakingEdgeLights> createState() => _SpeakingEdgeLightsState();
}

class _SpeakingEdgeLightsState extends State<SpeakingEdgeLights>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _motion,
          builder: (_, _) => CustomPaint(
            key: const Key('speaking_edge_canvas'),
            painter: _EdgePainter(_motion.value),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
}

class _EdgePainter extends CustomPainter {
  final double phase;
  const _EdgePainter(this.phase);
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final pulse = 0.65 + 0.35 * (0.5 + 0.5 * math.sin(phase * math.pi * 2));
    for (final right in [false, true]) {
      for (var band = 0; band < 3; band++) {
        final path = Path();
        for (double y = 0; y <= size.height; y += 5) {
          final envelope = math.sin(math.pi * y / size.height);
          final wave = math.sin(y / 55 - phase * math.pi * 2 + band * 0.9);
          final inset = 6 + band * 4 + (wave + 1) * 8 * envelope;
          final x = right ? size.width - inset : inset;
          if (y == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        final color = Color.lerp(
          const Color(0xFF187BFF),
          const Color(0xFF60D5FF),
          band / 3,
        )!;
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14
            ..color = color.withValues(alpha: 0.55 * pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.8
            ..color = color.withValues(alpha: (0.95 - band * 0.12) * pulse),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => old.phase != phase;
}
