import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_palette.dart';

/// Ege Merkezi afişi: sağda yumuşak ses dalgası halkaları ve katmanlı
/// dalgalar. Raster görsel yerine çizilir; tema ve vurgu rengine uyar.
class EgeBannerArt extends StatelessWidget {
  const EgeBannerArt({super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      key: const Key('ege_banner_art'),
      painter: _BannerPainter(
        accent: ChatPalette.accent,
        base: ChatPalette.surface,
        dark: ChatPalette.dark,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _BannerPainter extends CustomPainter {
  const _BannerPainter({
    required this.accent,
    required this.base,
    required this.dark,
  });

  final Color accent;
  final Color base;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final warm = Color.lerp(accent, const Color(0xFFE8B98A), 0.45)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            base,
            Color.lerp(base, warm, dark ? 0.10 : 0.16)!,
            Color.lerp(base, accent, dark ? 0.22 : 0.20)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // Sağ üstte ses halkaları.
    final center = Offset(size.width * 0.86, size.height * 0.42);
    for (var i = 0; i < 6; i++) {
      final r = size.height * (0.16 + i * 0.17);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = accent.withValues(alpha: (dark ? 0.34 : 0.28) * (1 - i / 7)),
      );
    }
    canvas.drawCircle(
      center,
      size.height * 0.12,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(accent, Colors.white, 0.45)!,
            accent,
          ],
        ).createShader(
          Rect.fromCircle(center: center, radius: size.height * 0.12),
        ),
    );

    // Altta katmanlı dalgalar.
    for (var band = 0; band < 3; band++) {
      final path = Path()..moveTo(size.width * 0.30, size.height);
      final amp = size.height * (0.07 + band * 0.03);
      final baseY = size.height * (0.80 - band * 0.10);
      for (double x = size.width * 0.30; x <= size.width; x += 4) {
        final t = (x - size.width * 0.30) / (size.width * 0.70);
        final y =
            baseY -
            math.sin(t * math.pi * (1.3 + band * 0.35) + band) * amp * t;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(
            accent,
            warm,
            band / 2,
          )!.withValues(alpha: dark ? 0.16 + band * 0.05 : 0.12 + band * 0.05),
      );
    }
  }

  @override
  bool shouldRepaint(_BannerPainter old) =>
      old.accent != accent || old.base != base || old.dark != dark;
}
