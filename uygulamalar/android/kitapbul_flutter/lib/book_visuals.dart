import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme_settings.dart';
import 'book_images.dart';
import 'catalog_store.dart';

/// Asenkron `BookImageStore` (hem tekil dosyalar hem `iphone_images_*.pack`)
/// için Flutter `ImageCache` dostu özel `ImageProvider`.
@immutable
class BookRefImage extends ImageProvider<BookRefImage> {
  const BookRefImage(this.ref);

  final String ref;

  @override
  Future<BookRefImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<BookRefImage>(this);

  @override
  ImageStreamCompleter loadImage(
    BookRefImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: key.ref,
    );
  }

  Future<ui.Codec> _loadAsync(
    BookRefImage key,
    ImageDecoderCallback decode,
  ) async {
    final store = BookImageStore.instance;
    final bytes = await store?.bytesOfAsync(key.ref);
    if (bytes == null || bytes.isEmpty) {
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('Kitap görseli bulunamadı: ${key.ref}');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is BookRefImage && other.ref == ref);

  @override
  int get hashCode => ref.hashCode;
}

/// Tactile press-scale wrapper with subtle haptic feedback.
class BouncyTap extends StatefulWidget {
  const BouncyTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDown = 0.96,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;
  final bool haptic;

  @override
  State<BouncyTap> createState() => _BouncyTapState();
}

class _BouncyTapState extends State<BouncyTap> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.scaleDown : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Smooth entrance animation (fade + gentle slide-up) for cards and tiles.
///
/// Only animates the first 10 items to avoid scroll-recycling flicker and frame
/// drops in large catalogs (e.g. 2,800+ books).
class StaggeredFadeSlide extends StatelessWidget {
  const StaggeredFadeSlide({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (index >= 10) return child;
    final clamped = index.clamp(0, 8);
    final durationMs = 220 + (clamped * 28);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: durationMs),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1.0 - t) * 14.0),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _TapRipple {
  _TapRipple(this.position, this.startedMs);
  final Offset position;
  final int startedMs;
}

/// Atmosferik kütüphane duvar kağıdı, kaydırma paralaksı, dokunma dalgaları
/// ve çok katmanlı ışık/yıldız/bokeh animasyon motoru.
class AmbientLibraryBackground extends StatefulWidget {
  const AmbientLibraryBackground({
    super.key,
    required this.wallpaperAsset,
    required this.particlesEnabled,
    this.clarity = WallpaperClarity.vivid,
    this.effectIntensity = EffectIntensity.rich,
    this.tapRipplesEnabled = true,
    this.scrollOffsetListenable,
    required this.child,
  });

  final String wallpaperAsset;
  final bool particlesEnabled;
  final WallpaperClarity clarity;
  final EffectIntensity effectIntensity;
  final bool tapRipplesEnabled;
  final ValueListenable<double>? scrollOffsetListenable;
  final Widget child;

  @override
  State<AmbientLibraryBackground> createState() =>
      _AmbientLibraryBackgroundState();
}

class _AmbientLibraryBackgroundState extends State<AmbientLibraryBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  );

  final List<_TapRipple> _ripples = [];
  int _clockMs = 0;

  EffectIntensity get _effectiveIntensity =>
      widget.particlesEnabled ? widget.effectIntensity : EffectIntensity.off;

  bool get _needsAnimation =>
      _effectiveIntensity != EffectIntensity.off || _ripples.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_needsAnimation) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AmbientLibraryBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_needsAnimation && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_needsAnimation && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spawnRipple(Offset localPos) {
    if (!widget.tapRipplesEnabled) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _clockMs = now;
    _ripples.removeWhere((r) => now - r.startedMs > 720);
    _ripples.add(_TapRipple(localPos, now));
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedAsset = resolveWallpaperAsset(widget.wallpaperAsset);
    final intensity = _effectiveIntensity;

    final scrimAlphas = switch ((widget.clarity, isDark)) {
      (WallpaperClarity.vivid, true) => (0.28, 0.16, 0.44),
      (WallpaperClarity.vivid, false) => (0.48, 0.30, 0.56),
      (WallpaperClarity.balanced, true) => (0.48, 0.34, 0.62),
      (WallpaperClarity.balanced, false) => (0.64, 0.48, 0.72),
      (WallpaperClarity.reading, true) => (0.72, 0.62, 0.84),
      (WallpaperClarity.reading, false) => (0.82, 0.72, 0.88),
    };

    Widget buildWallpaperLayer(double scrollPx) {
      if (resolvedAsset.isEmpty) return const SizedBox.shrink();
      final dy = -(scrollPx * 0.08).clamp(-26.0, 26.0);
      return Positioned.fill(
        child: IgnorePointer(
          child: ClipRect(
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: 1.09,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 520),
                  child: Image.asset(
                    resolvedAsset,
                    key: ValueKey(resolvedAsset),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.tapRipplesEnabled
          ? (e) => _spawnRipple(e.localPosition)
          : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (resolvedAsset.isNotEmpty)
            widget.scrollOffsetListenable != null
                ? ValueListenableBuilder<double>(
                    valueListenable: widget.scrollOffsetListenable!,
                    builder: (_, px, _) => buildWallpaperLayer(px),
                  )
                : buildWallpaperLayer(0.0),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.surface.withValues(alpha: scrimAlphas.$1),
                      scheme.primaryContainer.withValues(alpha: scrimAlphas.$2),
                      scheme.surface.withValues(alpha: scrimAlphas.$3),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
          if (intensity != EffectIntensity.off || _ripples.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (_, _) {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    _clockMs = now;
                    _ripples.removeWhere((r) => now - r.startedMs > 720);
                    if (!_needsAnimation && _controller.isAnimating) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted &&
                            !_needsAnimation &&
                            _controller.isAnimating) {
                          _controller.stop();
                        }
                      });
                    }
                    return CustomPaint(
                      painter: _LibraryAtmospherePainter(
                        progress: _controller.value,
                        primary: scheme.primary,
                        secondary: scheme.tertiary,
                        isDark: isDark,
                        intensity: intensity,
                        ripples: List<_TapRipple>.of(_ripples),
                        clockMs: _clockMs,
                      ),
                    );
                  },
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _LibraryAtmospherePainter extends CustomPainter {
  const _LibraryAtmospherePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.isDark,
    required this.intensity,
    required this.ripples,
    required this.clockMs,
  });

  final double progress;
  final Color primary;
  final Color secondary;
  final bool isDark;
  final EffectIntensity intensity;
  final List<_TapRipple> ripples;
  final int clockMs;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    if (intensity != EffectIntensity.off) {
      if (intensity == EffectIntensity.rich) {
        _drawLightBeams(canvas, size);
        _drawShootingSpark(canvas, size);
      }
      _drawStars(canvas, size);
      _drawMotes(canvas, size);
    }

    if (ripples.isNotEmpty) {
      _drawTapRipples(canvas);
    }
  }

  void _drawLightBeams(Canvas canvas, Size size) {
    final sway = math.sin(progress * math.pi * 2) * 0.04;
    for (var i = 0; i < 3; i++) {
      final topX = size.width * (0.16 + i * 0.30 + sway * (i.isEven ? 1 : -1));
      final spread = size.width * (0.24 + i * 0.04);
      final path = Path()
        ..moveTo(topX - spread * 0.25, 0)
        ..lineTo(topX + spread * 0.25, 0)
        ..lineTo(topX + spread * 0.95, size.height * 0.72)
        ..lineTo(topX - spread * 0.15, size.height * 0.72)
        ..close();

      final rayAlpha = (isDark ? 0.065 : 0.085) *
          (0.75 + 0.25 * math.sin(progress * math.pi * 4 + i * 1.4));
      final rayColor =
          (i == 1 ? primary : const Color(0xFFFDE68A)).withValues(alpha: rayAlpha);
      final paint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(topX, 0),
          Offset(topX, size.height * 0.72),
          [rayColor, rayColor.withValues(alpha: 0.0)],
        );
      canvas.drawPath(path, paint);
    }
  }

  void _drawStars(Canvas canvas, Size size) {
    final starCount = intensity == EffectIntensity.rich ? 44 : 18;
    final paint = Paint()..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < starCount; i++) {
      final s1 = ((i * 73 + 19) % 997) / 997.0;
      final s2 = ((i * 197 + 43) % 991) / 991.0;
      final x = s1 * size.width;
      final y = s2 * size.height * 0.48;
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin(progress * math.pi * 8 + i * 1.3));
      final alpha = (isDark ? 0.52 : 0.36) * twinkle;
      final r = i % 7 == 0 ? 2.2 : (i % 3 == 0 ? 1.5 : 1.0);
      final color = (i % 5 == 0 ? const Color(0xFFFDE68A) : Colors.white)
          .withValues(alpha: alpha);

      paint.color = color;
      canvas.drawCircle(Offset(x, y), r, paint);

      if (intensity == EffectIntensity.rich && i % 6 == 0) {
        final arm = 4.2 + twinkle * 4.5;
        linePaint.color = color.withValues(alpha: alpha * 0.85);
        canvas.drawLine(Offset(x - arm, y), Offset(x + arm, y), linePaint);
        canvas.drawLine(Offset(x, y - arm), Offset(x, y + arm), linePaint);
      }
    }
  }

  void _drawShootingSpark(Canvas canvas, Size size) {
    final cyc = (progress * 3.0) % 1.0;
    if (cyc > 0.24) return;
    final t = cyc / 0.24;
    final start = Offset(size.width * (0.18 + t * 0.52), size.height * (0.06 + t * 0.14));
    final tail = Offset(start.dx - 46 * (1.0 - t * 0.3), start.dy - 14 * (1.0 - t * 0.3));
    final alpha = math.sin(t * math.pi).clamp(0.0, 1.0) * (isDark ? 0.55 : 0.40);
    final p = Paint()
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(
        start,
        tail,
        [
          const Color(0xFFFDE68A).withValues(alpha: alpha),
          Colors.white.withValues(alpha: 0),
        ],
      );
    canvas.drawLine(start, tail, p);
  }

  void _drawMotes(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final count = intensity == EffectIntensity.rich ? 24 : 11;
    for (var i = 0; i < count; i++) {
      final seed = i * 1.6180339887;
      final baseX = ((seed * 37.0) % 1.0) * size.width;
      final speed = 0.55 + (i % 4) * 0.22;
      final phase = (progress * speed + (seed % 1.0)) % 1.0;
      final y = size.height * (1.04 - phase * 1.08);
      final sway = math.sin((progress * 2 * math.pi) + i) * 20.0;
      final radius = i % 6 == 0 ? 7.5 + (i % 3) * 2.5 : 2.6 + (i % 4) * 1.8;
      final alpha = (math.sin(phase * math.pi).clamp(0.0, 1.0)) *
          (isDark ? 0.26 : 0.19);
      final tint = switch (i % 3) {
        0 => const Color(0xFFFBBF24),
        1 => primary,
        _ => secondary,
      };
      paint.color = tint.withValues(alpha: alpha);
      final center = Offset(baseX + sway, y);
      canvas.drawCircle(center, radius, paint);
      if (i % 4 == 0) {
        paint.color = Colors.white.withValues(alpha: alpha * 0.9);
        canvas.drawCircle(center, radius * 0.34, paint);
      }
    }
  }

  void _drawTapRipples(Canvas canvas) {
    final strokePaint = Paint()..style = PaintingStyle.stroke;
    for (final ripple in ripples) {
      final elapsed = (clockMs - ripple.startedMs).clamp(0, 720);
      final t = elapsed / 720.0;
      final eased = 1.0 - math.pow(1.0 - t, 3.0);
      final fade = (1.0 - t).clamp(0.0, 1.0);
      strokePaint
        ..color = const Color(0xFFFDE68A).withValues(alpha: 0.45 * fade)
        ..strokeWidth = 2.2 * (1.0 - t * 0.5);
      canvas.drawCircle(ripple.position, 12.0 + eased * 64.0, strokePaint);
      strokePaint
        ..color = primary.withValues(alpha: 0.30 * fade)
        ..strokeWidth = 1.4;
      canvas.drawCircle(ripple.position, 6.0 + eased * 38.0, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LibraryAtmospherePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.intensity != intensity ||
      oldDelegate.ripples.length != ripples.length ||
      ripples.isNotEmpty;
}

/// Parıltı (shimmer) geçişli dikkat çekici aksiyon butonu.
class ShimmerActionButton extends StatefulWidget {
  const ShimmerActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.colors = const [Color(0xFF4F46E5), Color(0xFF7C3AED)],
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final List<Color> colors;

  @override
  State<ShimmerActionButton> createState() => _ShimmerActionButtonState();
}

class _ShimmerActionButtonState extends State<ShimmerActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BouncyTap(
      onTap: widget.onTap,
      child: Opacity(
        opacity: widget.onTap == null ? 0.55 : 1.0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: widget.colors.first.withValues(alpha: 0.34),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 21),
                    ),
                    const SizedBox(width: 11),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          if (widget.subtitle != null)
                            Text(
                              widget.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _shimmer,
                    builder: (_, _) {
                      final dx = -1.2 + (_shimmer.value * 2.4);
                      return FractionalTranslation(
                        translation: Offset(dx, 0),
                        child: Transform.rotate(
                          angle: 0.35,
                          child: Container(
                            width: 72,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.0),
                                  Colors.white.withValues(alpha: 0.22),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 3B illüstrasyonlu modül üst başlık kartı (Banko, Etiket, Nöbet, Raporlar vb.).
class IllustratedBannerCard extends StatelessWidget {
  const IllustratedBannerCard({
    super.key,
    required this.imageAsset,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.gradientColors = const [Color(0xFF1E1B4B), Color(0xFF4338CA)],
    this.pills = const [],
    this.trailing,
  });

  final String imageAsset;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final List<Widget> pills;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                imageAsset,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      gradientColors.first.withValues(alpha: 0.93),
                      gradientColors.last.withValues(alpha: 0.76),
                      gradientColors.first.withValues(alpha: 0.45),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(
                          icon,
                          color: const Color(0xFFFDE68A),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.86),
                                fontSize: 12.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  if (pills.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < pills.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            pills[i],
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animasyonlu halka (Donut) grafik bileşeni.
class AnimatedDonutChart extends StatelessWidget {
  const AnimatedDonutChart({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
    this.size = 156,
  });

  final List<({String label, int count, Color color})> slices;
  final String centerValue;
  final String centerLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, progress, _) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _DonutPainter(
                  slices: slices,
                  progress: progress,
                  trackColor: scheme.surfaceContainerHighest,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    centerValue,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    centerLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.slices,
    required this.progress,
    required this.trackColor,
  });

  final List<({String label, int count, Color color})> slices;
  final double progress;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 20.0;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

    final total = slices.fold<int>(0, (s, e) => s + e.count);
    if (total <= 0) return;

    var startAngle = -math.pi / 2;
    final maxSweep = 2 * math.pi * progress;
    var drawnSweep = 0.0;

    for (final slice in slices) {
      if (slice.count <= 0 || drawnSweep >= maxSweep) continue;
      final fullSliceSweep = (slice.count / total) * 2 * math.pi;
      final sweep = math.min(fullSliceSweep, maxSweep - drawnSweep);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = slice.color;
      canvas.drawArc(
        rect,
        startAngle,
        math.max(0.0, sweep - 0.025),
        false,
        p,
      );
      startAngle += fullSliceSweep;
      drawnSweep += fullSliceSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.slices != slices;
}

/// Animated integer counter pill for library statistics.
class AnimatedStatPill extends StatelessWidget {
  const AnimatedStatPill({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor = Colors.white,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: accentColor),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value.toDouble()),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text(
                  '${v.round()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.05,
                  ),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Arka plan görseli, cam parıltısı ve rozet destekli aksiyon kartı.
class GradientActionCard extends StatelessWidget {
  const GradientActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.imageAsset,
    this.badgeText,
    this.badgeColor,
    this.width = 160,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;
  final String? imageAsset;
  final String? badgeText;
  final Color? badgeColor;
  final double width;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageAsset != null && imageAsset!.isNotEmpty;
    return BouncyTap(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1.0,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.36),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
                if (hasImage)
                  Positioned.fill(
                    child: Image.asset(
                      imageAsset!,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                if (hasImage)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colors.first.withValues(alpha: 0.34),
                            Colors.black.withValues(alpha: 0.52),
                            Colors.black.withValues(alpha: 0.84),
                          ],
                          stops: const [0.0, 0.52, 1.0],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.24),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.center,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.32),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Icon(
                              icon,
                              color: const Color(0xFFFDE68A),
                              size: 18,
                            ),
                          ),
                          if (badgeText != null && badgeText!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: (badgeColor ?? colors.last)
                                    .withValues(alpha: 0.90),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                badgeText!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 9.5,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.90),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          shadows: const [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
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
    );
  }
}

const _coverPalettes = <List<Color>>[
  [Color(0xFF312E81), Color(0xFF4F46E5)], // Royal Indigo
  [Color(0xFF065F46), Color(0xFF10B981)], // Emerald Forest
  [Color(0xFF7F1D1D), Color(0xFFDC2626)], // Crimson Velvet
  [Color(0xFF78350F), Color(0xFFD97706)], // Warm Amber
  [Color(0xFF0C4A6E), Color(0xFF0284C7)], // Midnight Ocean
  [Color(0xFF581C87), Color(0xFF9333EA)], // Plum Orchid
  [Color(0xFF1E293B), Color(0xFF475569)], // Slate Classic
  [Color(0xFF134E4A), Color(0xFF0D9488)], // Deep Teal
];

List<Color> _paletteForTitle(String title) {
  var hash = 0;
  for (final code in title.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return _coverPalettes[hash % _coverPalettes.length];
}

bool hasStoredImage(dynamic raw) {
  if (BookImageStore.isRef(raw)) {
    return BookImageStore.instance?.hasFast(raw as String) == true;
  }
  return raw is String &&
      raw.isNotEmpty &&
      raw.length <= maxBookImageBase64Length;
}

Widget? _rawImageWidget(
  dynamic data, {
  BoxFit fit = BoxFit.cover,
  int? cacheWidth,
  Widget Function()? onError,
}) {
  try {
    if (BookImageStore.isRef(data)) {
      final ref = data as String;
      if (BookImageStore.instance?.hasFast(ref) == true) {
        final provider = ResizeImage.resizeIfNeeded(
          cacheWidth,
          null,
          BookRefImage(ref),
        );
        return Image(
          image: provider,
          fit: fit,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) =>
              onError != null ? onError() : const SizedBox.shrink(),
        );
      }
    } else if (data is String &&
        data.isNotEmpty &&
        data.length <= maxBookImageBase64Length) {
      return Image.memory(
        base64Decode(data),
        fit: fit,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) =>
            onError != null ? onError() : const SizedBox.shrink(),
      );
    }
  } catch (_) {}
  return null;
}

/// Stylized 3D hardcover book cover widget with high-DPI rendering,
/// realistic spine lighting, procedural fallback cover, and optional zoom badge.
class BookCoverWidget extends StatelessWidget {
  const BookCoverWidget({
    super.key,
    required this.book,
    this.width = 88,
    this.height = 128,
    this.imageField = 'coverBase64',
    this.heroTag,
    this.onTap,
    this.showZoomBadge = false,
  });

  final Map<String, dynamic> book;
  final double width;
  final double height;
  final String imageField;
  final String? heroTag;
  final VoidCallback? onTap;
  final bool showZoomBadge;

  Widget _buildProceduralCover() {
    final title = (book['title'] ?? 'Kitap').toString().trim();
    final author = (book['author'] ?? '').toString().trim();
    final category = (book['category'] ?? '').toString().trim();
    final palette = _paletteForTitle(title);
    final compact = width < 64;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: palette,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.all(compact ? 4 : 9),
      child: compact
          ? Center(
              child: Text(
                title.isEmpty ? 'K' : title.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFFFDE68A).withValues(alpha: 0.45),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (category.isNotEmpty && height >= 120)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        category.split('›').last.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFDE68A),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: height >= 150 ? 4 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: width >= 130 ? 13.5 : 10.5,
                          height: 1.18,
                          shadows: const [
                            Shadow(color: Colors.black45, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (author.isNotEmpty)
                    Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: width >= 130 ? 10.5 : 8.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(4),
      bottomLeft: const Radius.circular(4),
      topRight: Radius.circular(width >= 100 ? 12 : 8),
      bottomRight: Radius.circular(width >= 100 ? 12 : 8),
    );
    final decodeWidth = (width * 3.0).round().clamp(160, 720);
    final rawImg = _rawImageWidget(
      book[imageField],
      fit: BoxFit.cover,
      cacheWidth: decodeWidth,
      onError: _buildProceduralCover,
    );

    Widget content = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: width >= 100 ? 12 : 7,
            offset: Offset(2, width >= 100 ? 5 : 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            rawImg ?? _buildProceduralCover(),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: width >= 80 ? 9 : 5,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.28),
                        Colors.white.withValues(alpha: 0.24),
                        Colors.black.withValues(alpha: 0.14),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.28, 0.58, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            if (showZoomBadge && hasStoredImage(book[imageField]))
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.zoom_in_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (heroTag != null) {
      content = Hero(tag: heroTag!, child: content);
    }
    if (onTap != null) {
      return BouncyTap(onTap: onTap, child: content);
    }
    return content;
  }
}

/// Opens a full-screen frosted-glass lightbox for pinch-to-zoom inspection of
/// front cover, back cover, and imprint (künye) images.
Future<void> showBookCoverLightbox(
  BuildContext context,
  Map<String, dynamic> book, {
  String? heroTag,
  Future<Map<String, dynamic>?> Function()? onDownloadCover,
}) async {
  var currentBook = book;
  var selectedTab = 'coverBase64';
  var downloading = false;

  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, animation, _) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: StatefulBuilder(
            builder: (ctx, refresh) {
              final tabs = <(String, String)>[
                ('coverBase64', 'Ön Kapak'),
                if (hasStoredImage(currentBook['backCoverBase64']))
                  ('backCoverBase64', 'Arka Kapak'),
                if (hasStoredImage(currentBook['imprintBase64']))
                  ('imprintBase64', 'Künye'),
              ];
              if (!tabs.any((t) => t.$1 == selectedTab)) {
                selectedTab = 'coverBase64';
              }
              final fullImage = _rawImageWidget(
                currentBook[selectedTab],
                fit: BoxFit.contain,
              );

              return BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    title: Text(
                      '${currentBook['title'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                    actions: [
                      if (onDownloadCover != null &&
                          !hasStoredImage(currentBook['coverBase64']))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilledButton.tonalIcon(
                            onPressed: downloading
                                ? null
                                : () async {
                                    refresh(() => downloading = true);
                                    final updated = await onDownloadCover();
                                    if (!ctx.mounted) return;
                                    refresh(() {
                                      downloading = false;
                                      if (updated != null) {
                                        currentBook = updated;
                                      }
                                    });
                                  },
                            icon: downloading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download_outlined),
                            label: Text(
                              downloading ? 'İndiriliyor…' : 'Kapak İndir',
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  body: Column(
                    children: [
                      if (tabs.length > 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: SegmentedButton<String>(
                            style: SegmentedButton.styleFrom(
                              foregroundColor: Colors.white,
                              selectedForegroundColor: Colors.black,
                              selectedBackgroundColor: Colors.white,
                            ),
                            segments: [
                              for (final t in tabs)
                                ButtonSegment(value: t.$1, label: Text(t.$2)),
                            ],
                            selected: {selectedTab},
                            onSelectionChanged: (s) =>
                                refresh(() => selectedTab = s.first),
                          ),
                        ),
                      Expanded(
                        child: Center(
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4.5,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: fullImage != null
                                  ? (selectedTab == 'coverBase64' &&
                                            heroTag != null
                                        ? Hero(
                                            tag: heroTag,
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              child: fullImage,
                                            ),
                                          )
                                        : ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            child: fullImage,
                                          ))
                                  : BookCoverWidget(
                                      book: currentBook,
                                      width: 240,
                                      height: 348,
                                      heroTag: heroTag,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.82),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${currentBook['title'] ?? ''}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if ((currentBook['author'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty)
                                  currentBook['author'],
                                if ((currentBook['publisher'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty)
                                  currentBook['publisher'],
                                if ((currentBook['accessionCode'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty)
                                  'Demirbaş: ${currentBook['accessionCode']}',
                                if ((currentBook['isbn'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty)
                                  'ISBN: ${currentBook['isbn']}',
                              ].join(' · '),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Yakınlaştırmak için iki parmağınızla büyütün',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.52),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

/// Interactive or read-only 5-star rating bar for book cards, sheets, and editors.
class StarRatingRow extends StatelessWidget {
  const StarRatingRow({
    super.key,
    required this.rating,
    this.onChanged,
    this.size = 18,
    this.activeColor = const Color(0xFFF59E0B),
    this.showNumeric = false,
  });

  final int rating;
  final ValueChanged<int>? onChanged;
  final double size;
  final Color activeColor;
  final bool showNumeric;

  @override
  Widget build(BuildContext context) {
    final clamped = rating.clamp(0, 5);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          onChanged == null
              ? Icon(
                  i <= clamped
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: size,
                  color: i <= clamped ? activeColor : scheme.outlineVariant,
                )
              : InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onChanged!(i == clamped ? 0 : i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Icon(
                      i <= clamped
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: size,
                      color: i <= clamped ? activeColor : scheme.outlineVariant,
                    ),
                  ),
                ),
        if (showNumeric && clamped > 0) ...[
          const SizedBox(width: 4),
          Text(
            '$clamped/5',
            style: TextStyle(
              fontSize: size * 0.65,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact pill for displaying a small icon, value, and label inline.
class CompactStatChip extends StatelessWidget {
  const CompactStatChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.backgroundColor,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? foregroundColor ?? scheme.primary;
    final bg = backgroundColor ?? tint.withValues(alpha: 0.14);
    final fg = foregroundColor ?? tint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Secde Vakti Kutucuk stili yarı saydam buzlu cam yüzey + çapraz ışık parıltısı.
class FrostedGlassSurface extends StatelessWidget {
  const FrostedGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = EdgeInsets.zero,
    this.borderColor,
    this.tintColor,
    this.useBlur = false,
    this.opacity,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? tintColor;
  final bool useBlur;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseAlpha = opacity ?? (isDark ? 0.68 : 0.80);
    final bg = (tintColor ?? scheme.surfaceContainerLow).withValues(
      alpha: baseAlpha,
    );
    final edge = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.16)
            : scheme.outlineVariant.withValues(alpha: 0.55));

    Widget body = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: edge, width: 1.0),
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: isDark ? 0.08 : 0.34),
              bg,
            ),
            bg,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );

    if (useBlur) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 11, sigmaY: 11),
          child: body,
        ),
      );
    }
    return body;
  }
}

/// Resimli arka plan, cam parıltısı, simge rozeti ve canlı etiket sunan kare/dikdörtgen menü kartı.
class IllustratedSquareMenuCard extends StatelessWidget {
  const IllustratedSquareMenuCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.icon,
    required this.accentColors,
    required this.onTap,
    this.badge,
    this.height = 148,
  });

  final String title;
  final String subtitle;
  final String imageAsset;
  final IconData icon;
  final List<Color> accentColors;
  final VoidCallback? onTap;
  final String? badge;
  final double height;

  @override
  Widget build(BuildContext context) {
    return BouncyTap(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1.0,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.24),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColors.first.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: accentColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                if (imageAsset.isNotEmpty)
                  Image.asset(
                    imageAsset,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.14),
                        Colors.black.withValues(alpha: 0.48),
                        Colors.black.withValues(alpha: 0.88),
                      ],
                      stops: const [0.0, 0.48, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.center,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7.5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.36),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Icon(
                              icon,
                              color: const Color(0xFFFDE68A),
                              size: 18,
                            ),
                          ),
                          if (badge != null && badge!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3.5,
                              ),
                              decoration: BoxDecoration(
                                color: accentColors.last.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                badge!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 6,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 11,
                              height: 1.2,
                              shadows: const [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 5,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secde Vakti Halka stili 48 çentikli animasyonlu Kütüphane Nabız Kadranı.
class LibraryPulseDial extends StatefulWidget {
  const LibraryPulseDial({
    super.key,
    required this.ratio,
    required this.centerValue,
    required this.centerCaption,
    this.size = 94,
    this.alert = false,
    this.accent = const Color(0xFFFBBF24),
  });

  final double ratio;
  final String centerValue;
  final String centerCaption;
  final double size;
  final bool alert;
  final Color accent;

  @override
  State<LibraryPulseDial> createState() => _LibraryPulseDialState();
}

class _LibraryPulseDialState extends State<LibraryPulseDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _LibraryDialPainter(
                ratio: widget.ratio.clamp(0.0, 1.0),
                pulse: _pulse.value,
                accent: widget.alert ? const Color(0xFFF87171) : widget.accent,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.size * 0.16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.centerValue,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: widget.size * 0.195,
                        height: 1.05,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.centerCaption,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: widget.size * 0.105,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryDialPainter extends CustomPainter {
  const _LibraryDialPainter({
    required this.ratio,
    required this.pulse,
    required this.accent,
  });

  final double ratio;
  final double pulse;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final arcRadius = radius - 6.2;

    // İç kadran cam dolgusu — metnin çentiklerden net ayrılmasını sağlar
    canvas.drawCircle(
      center,
      math.max(8, arcRadius - 3.0),
      Paint()..color = Colors.black.withValues(alpha: 0.24),
    );

    // Dış yumuşak aura halkası
    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 + pulse * 2.4
      ..color = accent.withValues(alpha: 0.14 + pulse * 0.08);
    canvas.drawCircle(center, radius - 1.5, haloPaint);

    // 48 radyal kadran çentiği — dış halkada kalarak ortadaki sayıyla çakışmaz
    const tickCount = 48;
    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < tickCount; i++) {
      final frac = i / tickCount;
      final angle = -math.pi / 2 + frac * 2 * math.pi;
      final lit = frac <= ratio;
      final isMajor = i % 6 == 0;
      final inner = radius - (isMajor ? 3.8 : 2.3);
      final outer = radius;
      tickPaint
        ..strokeWidth = isMajor ? 1.6 : 1.0
        ..color = lit
            ? accent.withValues(alpha: 0.88)
            : Colors.white.withValues(alpha: 0.24);
      canvas.drawLine(
        Offset(center.dx + math.cos(angle) * inner,
            center.dy + math.sin(angle) * inner),
        Offset(center.dx + math.cos(angle) * outer,
            center.dy + math.sin(angle) * outer),
        tickPaint,
      );
    }

    // İlerleme yayının arka izi
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawCircle(center, arcRadius, trackPaint);

    // Ana ilerleme yayı
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..color = accent;
    final rect = Rect.fromCircle(center: center, radius: arcRadius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.max(0.08, ratio * 2 * math.pi),
      false,
      arcPaint,
    );

    // Parlayan uç nokta
    final tipAngle = -math.pi / 2 + ratio * 2 * math.pi;
    final tip = Offset(
      center.dx + math.cos(tipAngle) * arcRadius,
      center.dy + math.sin(tipAngle) * arcRadius,
    );
    canvas.drawCircle(
      tip,
      3.6 + pulse * 1.2,
      Paint()..color = accent.withValues(alpha: 0.42),
    );
    canvas.drawCircle(tip, 3.0, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LibraryDialPainter oldDelegate) =>
      oldDelegate.ratio != ratio ||
      oldDelegate.pulse != pulse ||
      oldDelegate.accent != accent;
}
