import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'jarvis_fx.dart';

enum OrbVisualState {
  idle,
  listening,
  thinking,
  speaking,
}

/// Animated Ege holographic core: rotating tick dial, segmented rings, an
/// audio-reactive wave ring, orbiting motes and a swirling energy core.
class JarvisOrb extends StatefulWidget {
  final double size;
  final OrbVisualState state;
  final double energy;
  final VoidCallback? onTap;

  const JarvisOrb({
    super.key,
    this.size = 180,
    this.state = OrbVisualState.idle,
    this.energy = 0.0,
    this.onTap,
  });

  @override
  State<JarvisOrb> createState() => _JarvisOrbState();
}

class _JarvisOrbState extends State<JarvisOrb>
    with SingleTickerProviderStateMixin, FxClockState<JarvisOrb> {
  @override
  int get fxFps => 60;

  static (Color, Color) _palette(OrbVisualState s) => switch (s) {
        OrbVisualState.idle => (const Color(0xFF22D3EE), const Color(0xFF0284C7)),
        OrbVisualState.listening => (const Color(0xFF38BDF8), const Color(0xFF67E8F9)),
        OrbVisualState.thinking => (const Color(0xFFA78BFA), const Color(0xFF38BDF8)),
        OrbVisualState.speaking => (const Color(0xFF34D399), const Color(0xFF22D3EE)),
      };

  IconData _centerIcon() => switch (widget.state) {
        OrbVisualState.idle => Icons.mic_none_rounded,
        OrbVisualState.listening => Icons.graphic_eq_rounded,
        OrbVisualState.thinking => Icons.auto_awesome_rounded,
        OrbVisualState.speaking => Icons.volume_up_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final (primary, secondary) = _palette(widget.state);
    const tint = Duration(milliseconds: 450);
    return Semantics(
      button: widget.onTap != null,
      label: 'Ege Çekirdek Orb',
      child: GestureDetector(
        onTap: widget.onTap == null
            ? null
            : () {
                JFx.haptic();
                widget.onTap!();
              },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: widget.energy.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 140),
            builder: (context, energy, _) => TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: primary),
              duration: tint,
              builder: (context, p, _) => TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: secondary),
                duration: tint,
                builder: (context, s, _) => RepaintBoundary(
                  child: CustomPaint(
                    painter: _OrbPainter(
                      clock: fxClock.seconds,
                      state: widget.state,
                      energy: energy,
                      primary: p ?? primary,
                      secondary: s ?? secondary,
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Icon(
                          _centerIcon(),
                          key: ValueKey(widget.state),
                          size: widget.size * 0.15,
                          color: const Color(0xFF03121F).withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.clock,
    required this.state,
    required this.energy,
    required this.primary,
    required this.secondary,
  }) : super(repaint: clock);

  final ValueListenable<double> clock;
  final OrbVisualState state;
  final double energy;
  final Color primary;
  final Color secondary;

  static const _violet = Color(0xFFA78BFA);

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;
    final speed = switch (state) {
      OrbVisualState.idle => 1.0,
      OrbVisualState.listening => 1.6,
      OrbVisualState.thinking => 2.8,
      OrbVisualState.speaking => 2.0,
    };
    final e = energy;
    final breathe = 0.5 + 0.5 * math.sin(t * 1.6 * speed);

    // 1. Ambient glow.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: 0.30 + e * 0.25 + breathe * 0.06),
            secondary.withValues(alpha: 0.10 + e * 0.08),
            Colors.transparent,
          ],
          stops: const [0.25, 0.62, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 2. Outer tick dial (slow rotation).
    final dialR = r * 0.93;
    final dialRot = t * 0.08 * speed;
    final minor = Path();
    final major = Path();
    for (var i = 0; i < 72; i++) {
      final a = dialRot + i * math.pi * 2 / 72;
      final isMajor = i % 6 == 0;
      final len = isMajor ? r * 0.075 : r * 0.035;
      final dir = Offset(math.cos(a), math.sin(a));
      (isMajor ? major : minor)
        ..moveTo(c.dx + dir.dx * dialR, c.dy + dir.dy * dialR)
        ..lineTo(c.dx + dir.dx * (dialR - len), c.dy + dir.dy * (dialR - len));
    }
    canvas.drawPath(
      minor,
      stroke
        ..strokeWidth = math.max(0.8, r * 0.009)
        ..color = primary.withValues(alpha: 0.45),
    );
    canvas.drawPath(
      major,
      stroke
        ..strokeWidth = math.max(1.4, r * 0.016)
        ..color = primary.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      c,
      dialR + r * 0.035,
      stroke
        ..strokeWidth = math.max(0.8, r * 0.008)
        ..color = primary.withValues(alpha: 0.35),
    );

    // 3. Segmented arcs (cyan + violet), counter-rotating, swelling with voice.
    final segR = r * 0.79 * (1 + e * 0.04);
    final segRot = -t * 0.35 * speed;
    final segRect = Rect.fromCircle(center: c, radius: segR);
    for (var i = 0; i < 4; i++) {
      final start = segRot + i * math.pi / 2;
      // glow pass
      canvas.drawArc(
        segRect,
        start,
        math.pi * 0.30,
        false,
        stroke
          ..strokeWidth = r * 0.075
          ..color = primary.withValues(alpha: 0.10 + e * 0.10),
      );
      canvas.drawArc(
        segRect,
        start,
        math.pi * 0.30,
        false,
        stroke
          ..strokeWidth = math.max(2.0, r * 0.032)
          ..color = primary.withValues(alpha: 0.92),
      );
      canvas.drawArc(
        segRect,
        start + math.pi * 0.36,
        math.pi * 0.10,
        false,
        stroke
          ..strokeWidth = math.max(1.6, r * 0.024)
          ..color = _violet.withValues(alpha: 0.80),
      );
    }

    // 4. Inner fine tick ring.
    final innerR = r * 0.655;
    final innerRot = t * 0.22 * speed;
    final inner = Path();
    for (var i = 0; i < 48; i++) {
      final a = innerRot + i * math.pi * 2 / 48;
      final dir = Offset(math.cos(a), math.sin(a));
      inner
        ..moveTo(c.dx + dir.dx * innerR, c.dy + dir.dy * innerR)
        ..lineTo(c.dx + dir.dx * (innerR - r * 0.03), c.dy + dir.dy * (innerR - r * 0.03));
    }
    canvas.drawPath(
      inner,
      stroke
        ..strokeWidth = math.max(0.8, r * 0.008)
        ..color = secondary.withValues(alpha: 0.55),
    );

    // 5. Thinking: radar sweep.
    if (state == OrbVisualState.thinking) {
      final sweepRect = Rect.fromCircle(center: c, radius: innerR);
      canvas.drawCircle(
        c,
        innerR - r * 0.015,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05
          ..shader = SweepGradient(
            colors: [Colors.transparent, primary.withValues(alpha: 0.75), Colors.transparent],
            stops: const [0.0, 0.18, 0.2],
            transform: GradientRotation(t * 2.4),
          ).createShader(sweepRect),
      );
    }

    // 6. Audio wave ring (listening / speaking).
    final waveR = r * 0.555;
    final amp = r * (0.006 + e * 0.055);
    final wave = Path();
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final a = i * math.pi * 2 / steps;
      final d = math.sin(a * 6 + t * 5.0) * 0.55 +
          math.sin(a * 9 - t * 3.7) * 0.30 +
          math.sin(a * 3 + t * 2.1) * 0.15;
      final rr = waveR + d * amp;
      final p = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
      if (i == 0) {
        wave.moveTo(p.dx, p.dy);
      } else {
        wave.lineTo(p.dx, p.dy);
      }
    }
    final voice = state == OrbVisualState.listening || state == OrbVisualState.speaking;
    canvas.drawPath(
      wave,
      stroke
        ..strokeWidth = math.max(1.2, r * 0.014)
        ..color = (voice ? primary : secondary).withValues(alpha: voice ? 0.55 + e * 0.4 : 0.28),
    );

    // 7. Orbiting motes on tilted ellipses.
    final mote = Paint();
    for (var i = 0; i < 3; i++) {
      final tilt = i * math.pi / 3 + 0.4;
      final a = t * (0.9 + i * 0.35) * speed + i * 2.1;
      final ex = math.cos(a) * r * 0.72;
      final ey = math.sin(a) * r * 0.26;
      final p = Offset(
        c.dx + ex * math.cos(tilt) - ey * math.sin(tilt),
        c.dy + ex * math.sin(tilt) + ey * math.cos(tilt),
      );
      final color = i == 1 ? _violet : primary;
      mote.color = color.withValues(alpha: 0.22);
      canvas.drawCircle(p, r * 0.055, mote);
      mote.color = Colors.white.withValues(alpha: 0.95);
      canvas.drawCircle(p, r * 0.018, mote);
    }

    // 8. Energy core.
    final coreR = r * 0.40 * (1 + e * 0.08 + breathe * 0.02);
    final coreRect = Rect.fromCircle(center: c, radius: coreR);
    canvas.drawCircle(
      c,
      coreR * 1.18,
      Paint()
        ..shader = RadialGradient(
          colors: [primary.withValues(alpha: 0.45 + e * 0.2), Colors.transparent],
        ).createShader(Rect.fromCircle(center: c, radius: coreR * 1.18)),
    );
    canvas.drawCircle(
      c,
      coreR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white,
            Color.lerp(Colors.white, primary, 0.35)!,
            primary,
            secondary.withValues(alpha: 0.95),
          ],
          stops: const [0.0, 0.28, 0.66, 1.0],
        ).createShader(coreRect),
    );
    // Swirl strands inside the core.
    canvas.save();
    canvas.clipPath(Path()..addOval(coreRect));
    final swirl = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = coreR * 0.09;
    for (var i = 0; i < 2; i++) {
      final rot = t * (0.9 + speed * 0.3) + i * math.pi;
      swirl.color = (i == 0 ? Colors.white : _violet).withValues(alpha: 0.35);
      canvas.drawArc(
        Rect.fromCircle(
          center: c + Offset(math.cos(rot) * coreR * 0.35, math.sin(rot) * coreR * 0.35),
          radius: coreR * 0.72,
        ),
        rot + math.pi * 0.6,
        math.pi * 0.9,
        false,
        swirl,
      );
    }
    canvas.restore();
    // Rim + specular highlight.
    canvas.drawCircle(
      c,
      coreR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.012)
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    final hl = c + Offset(-coreR * 0.32, -coreR * 0.36);
    canvas.drawCircle(
      hl,
      coreR * 0.42,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.55), Colors.transparent],
        ).createShader(Rect.fromCircle(center: hl, radius: coreR * 0.42)),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.energy != energy ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary;
}
