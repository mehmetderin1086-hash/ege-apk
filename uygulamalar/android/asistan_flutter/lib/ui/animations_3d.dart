import 'dart:math' as math;

import 'package:flutter/material.dart';

enum OrbActivityState { idle, listening, thinking, speaking }

class HolographicOrb3D extends StatefulWidget {
  const HolographicOrb3D({
    super.key,
    this.size = 240,
    this.state = OrbActivityState.idle,
    this.audioLevel = 0.0,
    this.primaryColor = const Color(0xFF00E5FF),
    this.secondaryColor = const Color(0xFFFF2E93),
    this.tertiaryColor = const Color(0xFF8B5CF6),
    this.onTap,
    this.interactive = true,
  });

  final double size;
  final OrbActivityState state;
  final double audioLevel;
  final Color primaryColor;
  final Color secondaryColor;
  final Color tertiaryColor;
  final VoidCallback? onTap;
  final bool interactive;

  @override
  State<HolographicOrb3D> createState() => _HolographicOrb3DState();
}

class _HolographicOrb3DState extends State<HolographicOrb3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _userRotX = 0.25;
  double _userRotY = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onPanUpdate: widget.interactive
          ? (details) {
              setState(() {
                _userRotY += details.delta.dx * 0.012;
                _userRotX = (_userRotX - details.delta.dy * 0.012).clamp(
                  -1.3,
                  1.3,
                );
              });
            }
          : null,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _HolographicOrbPainter(
                progress: _controller.value,
                state: widget.state,
                audioLevel: widget.audioLevel.clamp(0.0, 1.0),
                userRotX: _userRotX,
                userRotY: _userRotY,
                primaryColor: widget.primaryColor,
                secondaryColor: widget.secondaryColor,
                tertiaryColor: widget.tertiaryColor,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Point3D {
  const _Point3D(this.x, this.y, this.z, this.colorIndex);
  final double x;
  final double y;
  final double z;
  final int colorIndex;
}

class _HolographicOrbPainter extends CustomPainter {
  _HolographicOrbPainter({
    required this.progress,
    required this.state,
    required this.audioLevel,
    required this.userRotX,
    required this.userRotY,
    required this.primaryColor,
    required this.secondaryColor,
    required this.tertiaryColor,
  });

  final double progress;
  final OrbActivityState state;
  final double audioLevel;
  final double userRotX;
  final double userRotY;
  final Color primaryColor;
  final Color secondaryColor;
  final Color tertiaryColor;

  static final List<_Point3D> _baseSpherePoints = _generateFibonacciSphere(140);

  static List<_Point3D> _generateFibonacciSphere(int count) {
    final pts = <_Point3D>[];
    final phi = math.pi * (3.0 - math.sqrt(5.0));
    for (int i = 0; i < count; i++) {
      final y = 1.0 - (i / (count - 1)) * 2.0;
      final radius = math.sqrt(math.max(0.0, 1.0 - y * y));
      final theta = phi * i;
      final x = math.cos(theta) * radius;
      final z = math.sin(theta) * radius;
      pts.add(_Point3D(x, y, z, i % 3));
    }
    return pts;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.shortestSide * 0.34;

    final speedMult = switch (state) {
      OrbActivityState.idle => 1.0,
      OrbActivityState.listening => 2.2,
      OrbActivityState.thinking => 3.4,
      OrbActivityState.speaking => 2.6,
    };

    final t = progress * math.pi * 2.0 * speedMult;
    final dynamicAmp = switch (state) {
      OrbActivityState.idle => 0.04,
      OrbActivityState.listening => 0.12 + audioLevel * 0.25,
      OrbActivityState.thinking => 0.16,
      OrbActivityState.speaking => 0.18 + audioLevel * 0.22,
    };

    final pulseScale =
        1.0 +
        math.sin(t * 2.0) * 0.04 +
        (state == OrbActivityState.listening ||
                state == OrbActivityState.speaking
            ? audioLevel * 0.16
            : 0.0);
    final radius = baseRadius * pulseScale;

    // 1. Volumetric Outer Glow Halo
    final outerGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryColor.withValues(alpha: 0.36),
          secondaryColor.withValues(alpha: 0.20),
          tertiaryColor.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.42, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.48));
    canvas.drawCircle(center, radius * 1.48, outerGlowPaint);

    // 2. Siri-style Liquid Ribbon Waves inside the core
    _drawSiriLiquidRibbons(canvas, center, radius, t, dynamicAmp);

    // 3. 3D Gyroscope Orbital Rings
    _draw3DOrbitalRing(
      canvas: canvas,
      center: center,
      radius: radius * 1.18,
      rotX: userRotX + t * 0.7,
      rotY: userRotY + t * 0.5,
      rotZ: t * 0.3,
      color: primaryColor,
    );
    _draw3DOrbitalRing(
      canvas: canvas,
      center: center,
      radius: radius * 1.08,
      rotX: -userRotX - t * 0.5 + 1.0,
      rotY: userRotY - t * 0.8,
      rotZ: -t * 0.6,
      color: secondaryColor,
    );
    if (state != OrbActivityState.idle) {
      _draw3DOrbitalRing(
        canvas: canvas,
        center: center,
        radius: radius * 1.26,
        rotX: t * 1.1,
        rotY: -t * 0.9,
        rotZ: t * 0.4,
        color: tertiaryColor,
      );
    }

    // 4. 3D Perspective-Projected Fibonacci Sphere Particles & Neural Links
    final rotY = userRotY + t * 0.6;
    final rotX = userRotX + math.sin(t * 0.5) * 0.25;
    final cosY = math.cos(rotY);
    final sinY = math.sin(rotY);
    final cosX = math.cos(rotX);
    final sinX = math.sin(rotX);

    final projected = <({Offset pos, double z, Color color, double scale})>[];
    for (int i = 0; i < _baseSpherePoints.length; i++) {
      final p = _baseSpherePoints[i];
      final wave =
          1.0 +
          dynamicAmp *
              math.sin(p.x * 4.0 + t * 2.0) *
              math.cos(p.y * 4.0 - t * 1.5);
      final vx = p.x * wave;
      final vy = p.y * wave;
      final vz = p.z * wave;

      // Rotate around Y then X
      final x1 = vx * cosY - vz * sinY;
      final z1 = vz * cosY + vx * sinY;
      final y2 = vy * cosX - z1 * sinX;
      final z2 = z1 * cosX + vy * sinX;

      // Perspective projection
      const fov = 2.8;
      final depth = (fov / (fov - z2 * 0.85)).clamp(0.5, 2.2);
      final sx = center.dx + x1 * radius * depth * 0.82;
      final sy = center.dy + y2 * radius * depth * 0.82;

      final baseColor = switch (p.colorIndex) {
        0 => primaryColor,
        1 => secondaryColor,
        _ => tertiaryColor,
      };
      projected.add((
        pos: Offset(sx, sy),
        z: z2,
        color: baseColor,
        scale: depth,
      ));
    }

    projected.sort((a, b) => a.z.compareTo(b.z));

    // Draw subtle neural connections between nearby front-facing nodes
    final linePaint = Paint()..strokeWidth = 0.85;
    for (int i = projected.length - 1; i >= projected.length ~/ 2; i--) {
      final a = projected[i];
      for (int j = i - 1; j >= math.max(0, i - 10); j--) {
        final b = projected[j];
        final dist = (a.pos - b.pos).distance;
        if (dist < radius * 0.34) {
          final alpha = ((1.0 - dist / (radius * 0.34)) * 0.26).clamp(
            0.0,
            0.35,
          );
          linePaint.color = a.color.withValues(alpha: alpha);
          canvas.drawLine(a.pos, b.pos, linePaint);
        }
      }
    }

    // Draw 3D particles
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final pt in projected) {
      final normZ = ((pt.z + 1.2) / 2.4).clamp(0.15, 1.0);
      final dotRadius =
          (1.3 + normZ * 2.2) * (size.shortestSide / 220.0).clamp(0.6, 1.5);
      dotPaint.color = pt.color.withValues(
        alpha: (0.25 + normZ * 0.72).clamp(0.0, 1.0),
      );
      canvas.drawCircle(pt.pos, dotRadius, dotPaint);
    }

    // 5. Inner Specular Core Highlight
    final corePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        colors: [
          Colors.white.withValues(alpha: 0.55),
          primaryColor.withValues(alpha: 0.25),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.52));
    canvas.drawCircle(center, radius * 0.52, corePaint);
  }

  void _drawSiriLiquidRibbons(
    Canvas canvas,
    Offset center,
    double radius,
    double t,
    double amp,
  ) {
    final colors = [primaryColor, secondaryColor, tertiaryColor];
    for (int r = 0; r < 3; r++) {
      final path = Path();
      const steps = 60;
      final phase = r * (math.pi * 2 / 3) + t * (1.2 + r * 0.3);
      for (int i = 0; i <= steps; i++) {
        final angle = (i / steps) * math.pi * 2;
        final wave =
            math.sin(angle * 3 + phase) * 0.16 +
            math.cos(angle * 2 - phase * 0.8) * (0.10 + amp * 0.5);
        final rad = radius * (0.62 + wave);
        final x = center.dx + math.cos(angle) * rad;
        final y = center.dy + math.sin(angle) * rad;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();

      final ribbonPaint = Paint()
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            colors[r].withValues(alpha: 0.28),
            colors[(r + 1) % 3].withValues(alpha: 0.08),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawPath(path, ribbonPaint);
    }
  }

  void _draw3DOrbitalRing({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required double rotX,
    required double rotY,
    required double rotZ,
    required Color color,
  }) {
    final path = Path();
    const segments = 64;
    final cx = math.cos(rotX), sx = math.sin(rotX);
    final cy = math.cos(rotY), sy = math.sin(rotY);
    final cz = math.cos(rotZ), sz = math.sin(rotZ);

    for (int i = 0; i <= segments; i++) {
      final theta = (i / segments) * math.pi * 2;
      double x = math.cos(theta) * radius;
      double y = math.sin(theta) * radius;
      double z = 0.0;

      // Rotate X
      final y1 = y * cx - z * sx;
      final z1 = y * sx + z * cx;
      y = y1;
      z = z1;

      // Rotate Y
      final x2 = x * cy + z * sy;
      final z2 = -x * sy + z * cy;
      x = x2;
      z = z2;

      // Rotate Z
      final x3 = x * cz - y * sz;
      final y3 = x * sz + y * cz;

      final pt = Offset(center.dx + x3, center.dy + y3);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.42);
    canvas.drawPath(path, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _HolographicOrbPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.state != state ||
        oldDelegate.audioLevel != audioLevel ||
        oldDelegate.userRotX != userRotX ||
        oldDelegate.userRotY != userRotY;
  }
}

/// Siri Apple Intelligence Edge Glow + Google Assistant 4-Color Light Bar
class SiriEdgeGlowOverlay extends StatefulWidget {
  const SiriEdgeGlowOverlay({
    super.key,
    required this.active,
    this.audioLevel = 0.0,
    required this.child,
  });

  final bool active;
  final double audioLevel;
  final Widget child;

  @override
  State<SiriEdgeGlowOverlay> createState() => _SiriEdgeGlowOverlayState();
}

class _SiriEdgeGlowOverlayState extends State<SiriEdgeGlowOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.active)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final angle = _controller.value * math.pi * 2;
                final thickness = 5.0 + (widget.audioLevel * 8.0);
                return CustomPaint(
                  painter: _SiriPerimeterPainter(
                    angle: angle,
                    thickness: thickness,
                    audioLevel: widget.audioLevel,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SiriPerimeterPainter extends CustomPainter {
  _SiriPerimeterPainter({
    required this.angle,
    required this.thickness,
    required this.audioLevel,
  });

  final double angle;
  final double thickness;
  final double audioLevel;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(thickness / 2),
      const Radius.circular(24),
    );

    final sweepGradient = SweepGradient(
      transform: GradientRotation(angle),
      colors: const [
        Color(0xFF00E5FF),
        Color(0xFF4285F4),
        Color(0xFFA855F7),
        Color(0xFFFF2E93),
        Color(0xFFFBBC05),
        Color(0xFF34A853),
        Color(0xFF00E5FF),
      ],
    );

    // Outer blurred Siri glow
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness * 2.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
      ..shader = sweepGradient.createShader(rect);
    canvas.drawRRect(rrect, glowPaint);

    // Crisp inner perimeter line
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness * 0.75
      ..shader = sweepGradient.createShader(rect);
    canvas.drawRRect(rrect, borderPaint);

    // Google Assistant 4-color bottom light bar
    final barWidth = size.width * (0.58 + audioLevel * 0.25);
    final barRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height - 6),
      width: barWidth,
      height: 5.0 + audioLevel * 4.0,
    );
    final googleGradient = const LinearGradient(
      colors: [
        Color(0xFF4285F4), // Google Blue
        Color(0xFFEA4335), // Google Red
        Color(0xFFFBBC05), // Google Yellow
        Color(0xFF34A853), // Google Green
      ],
    );
    final barPaint = Paint()
      ..shader = googleGradient.createShader(barRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(8)),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SiriPerimeterPainter oldDelegate) {
    return oldDelegate.angle != angle ||
        oldDelegate.thickness != thickness ||
        oldDelegate.audioLevel != audioLevel;
  }
}
