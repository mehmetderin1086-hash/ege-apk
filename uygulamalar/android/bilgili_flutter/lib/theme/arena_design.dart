import 'dart:math';
import 'package:flutter/material.dart';

/// Zirve Merdiveni × İstanbul Gecesi ortak stüdyo renk paleti.
class StudioPalette {
  static const Color gold = Color(0xFFF2C14E);
  static const Color goldBright = Color(0xFFFFE28A);
  static const Color goldDeep = Color(0xFFB57C14);
  static const Color navyLight = Color(0xFF2033A3);
  static const Color navyTop = Color(0xFF1A2A8E);
  static const Color navyMid = Color(0xFF0B1450);
  static const Color navyDark = Color(0xFF060B2E);
  static const Color night = Color(0xFF03061C);
  static const Color sapphire = Color(0xFF5AA9FF);
  static const Color amber = Color(0xFFFF9A1F);
  static const Color emerald = Color(0xFF22B455);
  static const Color crimson = Color(0xFFD6333F);
}

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
  subtle('Hafif', 0.30),
  balanced('Dengeli', 0.46),
  vivid('Canlı', 0.64),
  crisp('Tam Net', 0.80);

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
      id: 'istanbul_bogaz',
      title: 'İstanbul Boğazı',
      subtitle: '15 Temmuz Köprüsü · Altın Zirve Stüdyosu',
      assetPath: 'assets/images/istanbul_bogaz.webp',
      primary: StudioPalette.gold,
      secondary: StudioPalette.sapphire,
      surface: StudioPalette.navyMid,
      ink: StudioPalette.night,
    ),
    ArenaWallpaper(
      id: 'istanbul_kiz_kulesi',
      title: 'Kız Kulesi Gecesi',
      subtitle: 'Boğaz ışıkları ve altın yansımalar',
      assetPath: 'assets/images/istanbul_kiz_kulesi.webp',
      primary: StudioPalette.gold,
      secondary: Color(0xFF4CE0D2),
      surface: StudioPalette.navyMid,
      ink: StudioPalette.night,
    ),
    ArenaWallpaper(
      id: 'istanbul_galata',
      title: 'Galata & Haliç',
      subtitle: 'Tarihi kule ve Haliç gece silueti',
      assetPath: 'assets/images/istanbul_galata.webp',
      primary: StudioPalette.gold,
      secondary: Color(0xFFFF9A1F),
      surface: Color(0xFF101958),
      ink: StudioPalette.night,
    ),
    ArenaWallpaper(
      id: 'istanbul_ayasofya',
      title: 'Tarihi Yarımada',
      subtitle: 'Ayasofya ve Sultanahmet yıldızlı gece',
      assetPath: 'assets/images/istanbul_ayasofya.webp',
      primary: StudioPalette.gold,
      secondary: Color(0xFF7BC4FF),
      surface: Color(0xFF0E1752),
      ink: StudioPalette.night,
    ),
    ArenaWallpaper(
      id: 'istanbul_ortakoy',
      title: 'Ortaköy Sahili',
      subtitle: 'Boğaz kıyısında altın cami ve köprü',
      assetPath: 'assets/images/istanbul_ortakoy.webp',
      primary: StudioPalette.gold,
      secondary: StudioPalette.sapphire,
      surface: StudioPalette.navyMid,
      ink: StudioPalette.night,
    ),
    ArenaWallpaper(
      id: 'istanbul_skyline',
      title: 'İstanbul Sahnesi',
      subtitle: 'Tarihi Yarımada üzerinde stüdyo ışıkları',
      assetPath: 'assets/images/istanbul_skyline.webp',
      primary: StudioPalette.gold,
      secondary: Color(0xFF66B2FF),
      surface: StudioPalette.navyTop,
      ink: StudioPalette.night,
    ),
    ArenaWallpaper(
      id: 'istanbul_dolmabahce',
      title: 'Dolmabahçe Sarayı',
      subtitle: 'Boğazda altın saray ve yansıma',
      assetPath: 'assets/images/istanbul_dolmabahce.webp',
      primary: StudioPalette.gold,
      secondary: Color(0xFFFFB454),
      surface: StudioPalette.navyMid,
      ink: StudioPalette.night,
    ),
    ArenaWallpaper(
      id: 'istanbul_suleymaniye',
      title: 'Süleymaniye & Haliç',
      subtitle: 'Altın kubbeler ve Haliç köprüleri',
      assetPath: 'assets/images/istanbul_suleymaniye.webp',
      primary: StudioPalette.gold,
      secondary: StudioPalette.sapphire,
      surface: StudioPalette.navyMid,
      ink: StudioPalette.night,
    ),
    ArenaWallpaper(
      id: 'studyo',
      title: 'Gece Stüdyosu',
      subtitle: 'Lacivert sahne ışıkları, altın vurgular',
      primary: StudioPalette.gold,
      secondary: StudioPalette.sapphire,
      surface: Color(0xFF14207A),
      ink: StudioPalette.night,
      gradient: [Color(0xFF1C2C8C), Color(0xFF0B1450), Color(0xFF060A2E), Color(0xFF03061C)],
    ),
    ArenaWallpaper(
      id: 'observatory',
      title: 'Gök Kubbe',
      subtitle: 'Yıldızlı rasathane ve altın usturlap',
      assetPath: 'assets/images/scene_observatory.webp',
      primary: StudioPalette.gold,
      secondary: Color(0xFF4CE0D2),
      surface: Color(0xFF0E1B33),
      ink: Color(0xFF060C1A),
    ),
    ArenaWallpaper(
      id: 'pure_night',
      title: 'Saf Gece',
      subtitle: 'Odaklı okuma için dingin lacivert',
      assetPath: null,
      primary: StudioPalette.gold,
      secondary: StudioPalette.sapphire,
      surface: StudioPalette.navyMid,
      ink: StudioPalette.night,
    ),
  ];

  static ArenaWallpaper byId(String id) {
    return catalog.firstWhere((w) => w.id == id, orElse: () => catalog.first);
  }
}

/// Tüm uygulama genelinde kullanılan İstanbul × Zirve Merdiveni 3D stüdyo arka planı.
class ArenaAmbientBackground extends StatefulWidget {
  final ArenaWallpaper wallpaper;
  final WallpaperClarity clarity;
  final EffectIntensity intensity;
  final bool reduceMotion;
  final String? overrideAssetPath;
  final Widget child;

  const ArenaAmbientBackground({
    super.key,
    required this.wallpaper,
    required this.clarity,
    required this.intensity,
    this.reduceMotion = false,
    this.overrideAssetPath,
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
      duration: const Duration(seconds: 18),
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
    if (widget.reduceMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        widget.intensity == EffectIntensity.off) {
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
    final asset = widget.overrideAssetPath ?? wp.assetPath;
    final animate = !widget.reduceMotion &&
        !MediaQuery.disableAnimationsOf(context) &&
        widget.intensity != EffectIntensity.off;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Zirve Merdiveni derin radyal lacivert stüdyo tabanı
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: wp.gradient != null
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: wp.gradient!,
                  )
                : const RadialGradient(
                    center: Alignment(0, -0.35),
                    radius: 1.25,
                    colors: [
                      StudioPalette.navyTop,
                      StudioPalette.navyMid,
                      StudioPalette.night,
                    ],
                    stops: [0.0, 0.48, 1.0],
                  ),
          ),
        ),

        // 2. İstanbul gece panoraması (3D derinlikli hafif Ken Burns paralaksı)
        if (asset != null)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, img) {
              if (!animate) return img!;
              final phase = _ctrl.value * 2 * pi;
              final scale = 1.07 + 0.024 * sin(phase);
              final dx = 6.0 * sin(phase);
              final dy = 5.0 * cos(phase * 0.75);
              final tiltY = 0.015 * sin(phase);
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0008)
                  ..rotateY(tiltY)
                  ..translateByDouble(dx, dy, 0, 1)
                  ..scaleByDouble(scale, scale, 1, 1),
                child: img,
              );
            },
            child: Opacity(
              opacity: min(1.0, widget.clarity.opacity + 0.14),
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),

        // 3. Zirve Merdiveni stüdyo derinlik perdesi (İstanbul görünür + metinler keskin)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.32, 0.72, 1.0],
              colors: [
                StudioPalette.night.withValues(alpha: 0.42),
                StudioPalette.navyMid.withValues(alpha: 0.34),
                StudioPalette.navyDark.withValues(alpha: 0.62),
                StudioPalette.night.withValues(alpha: 0.88),
              ],
            ),
          ),
        ),

        // 4. Süpüren Zirve Merdiveni 3D ışık huzmeleri, altın Boğaz parıltıları ve sahne zemini
        if (widget.intensity != EffectIntensity.off)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => CustomPaint(
                painter: _IstanbulStudioStagePainter(
                  progress: animate ? _ctrl.value : 0.18,
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

class _IstanbulStudioStagePainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final double factor;

  const _IstanbulStudioStagePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.factor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * pi;

    // A) Zirve Merdiveni tarzı süpüren stüdyo ışık huzmeleri (altın + safir)
    for (var k = 0; k < 4; k++) {
      final isGold = k.isEven;
      final angle = sin(t * (isGold ? 1.0 : 0.8) + k * 1.55) * 0.36;
      final origin = Offset(size.width * (0.12 + 0.25 * k), -24);
      final len = size.height * 1.15;
      final spread = isGold ? 0.11 : 0.14;
      final beam = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + sin(angle - spread) * len, origin.dy + cos(angle - spread) * len)
        ..lineTo(origin.dx + sin(angle + spread) * len, origin.dy + cos(angle + spread) * len)
        ..close();
      final beamColor = isGold ? primary : secondary;
      canvas.drawPath(
        beam,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              beamColor.withValues(alpha: (isGold ? 0.15 : 0.17) * factor),
              beamColor.withValues(alpha: 0.03 * factor),
              Colors.transparent,
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(Offset.zero & size),
      );
    }

    // B) Üst stüdyo 3D altın yörünge halkaları
    final haloCenter = Offset(size.width * 0.5, -size.width * 0.16);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = primary.withValues(alpha: 0.14 * factor);
    for (var i = 0; i < 2; i++) {
      final rx = size.width * (0.48 + i * 0.16);
      final ry = rx * 0.32;
      canvas.drawOval(
        Rect.fromCenter(center: haloCenter, width: rx * 2, height: ry * 2),
        ringPaint,
      );
      final a = t * (i == 0 ? 1.0 : -0.75) + i * 2.0;
      final dot = Offset(haloCenter.dx + cos(a) * rx, haloCenter.dy + sin(a) * ry);
      canvas.drawCircle(
        dot,
        3.2,
        Paint()..color = (i == 0 ? primary : secondary).withValues(alpha: 0.65 * factor),
      );
    }

    // C) Alt 3D perspektif stüdyo ışık çizgileri (derinlik hissi)
    final horizonY = size.height * 0.84;
    final gridPaint = Paint()
      ..strokeWidth = 0.8
      ..color = primary.withValues(alpha: 0.08 * factor);
    for (var i = -3; i <= 3; i++) {
      canvas.drawLine(
        Offset(size.width * 0.5 + i * 28, horizonY),
        Offset(size.width * 0.5 + i * 115, size.height),
        gridPaint,
      );
    }

    // D) Boğaz altın ışıltıları & yüzen yıldız tozları
    for (var i = 0; i < 22; i++) {
      final bx = ((i * 57 + 13) % 100) / 100.0 * size.width;
      final by = ((i * 39 + 17) % 100) / 100.0 * size.height;
      final driftY = (by - progress * 64 * (0.8 + (i % 3) * 0.35)) % size.height;
      final y = driftY < 0 ? driftY + size.height : driftY;
      final twinkle = (0.25 + 0.75 * (0.5 + 0.5 * sin(t * 2 + i * 1.4))) * factor;
      final color = i % 3 == 0 ? primary : (i.isEven ? Colors.white : secondary);
      final radius = i % 5 == 0 ? 2.4 : 1.3;
      canvas.drawCircle(
        Offset(bx, y),
        radius,
        Paint()..color = color.withValues(alpha: 0.34 * twinkle),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IstanbulStudioStagePainter old) =>
      old.progress != progress || old.primary != primary || old.factor != factor;
}

/// 2 eksenli gerçek 3D perspektif eğimi ve fiziksel basma derinliği.
class ArenaPressDepth extends StatefulWidget {
  final Widget child;
  final double depthOffset;
  const ArenaPressDepth({super.key, required this.child, this.depthOffset = 2.6});

  @override
  State<ArenaPressDepth> createState() => _ArenaPressDepthState();
}

class _ArenaPressDepthState extends State<ArenaPressDepth> {
  Offset? _origin;
  double _tiltX = 0;
  double _tiltY = 0;

  void _reset() {
    if (_origin != null) {
      setState(() {
        _origin = null;
        _tiltX = 0;
        _tiltY = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final pressed = _origin != null;
    final scale = pressed ? 0.972 : 1.0;
    final dy = pressed ? widget.depthOffset : 0.0;
    return Listener(
      onPointerDown: (event) => setState(() {
        _origin = event.position;
        final sz = context.size;
        final w = max(1.0, sz?.width ?? 1.0);
        final h = max(1.0, sz?.height ?? 1.0);
        _tiltY = ((event.localPosition.dx / w) - 0.5).clamp(-0.5, 0.5) * 0.09;
        _tiltX = -((event.localPosition.dy / h) - 0.5).clamp(-0.5, 0.5) * 0.08;
      }),
      onPointerMove: (event) {
        if (_origin != null && (event.position - _origin!).distance > 14) _reset();
      },
      onPointerUp: (_) => _reset(),
      onPointerCancel: (_) => _reset(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 115),
        curve: Curves.easeOutCubic,
        transformAlignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0018)
          ..rotateX(_tiltX)
          ..rotateY(_tiltY)
          ..translateByDouble(0.0, dy, 0.0, 1.0)
          ..scaleByDouble(scale, scale, 1.0, 1.0),
        child: widget.child,
      ),
    );
  }
}

/// 3D perspektif giriş animasyonu (soru kartları, seçenekler ve özet kartları için).
class Studio3DEntrance extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final double initialTiltX;

  const Studio3DEntrance({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 340),
    this.initialTiltX = 0.20,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Curves.easeOutBack,
      builder: (context, value, content) {
        final clamped = value.clamp(0.0, 1.0);
        final tilt = (1.0 - clamped) * initialTiltX;
        final dy = (1.0 - clamped) * 14.0;
        final scale = 0.94 + 0.06 * clamped;
        return Opacity(
          opacity: clamped,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0016)
              ..rotateX(tilt)
              ..translateByDouble(0.0, dy, 0.0, 1.0)
              ..scaleByDouble(scale, scale, 1.0, 1.0),
            child: content,
          ),
        );
      },
      child: child,
    );
  }
}

/// 3D parlayan stüdyo düğme renk varyantları.
enum StudioButtonVariant { gold, navy, emerald, amber, crimson }

/// Fiziksel 3D çıkıntılı, metalik parlama efektli Zirve Merdiveni düğmesi.
class Studio3DButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final StudioButtonVariant variant;
  final bool expand;
  final bool shimmer;
  final EdgeInsetsGeometry? padding;
  final double fontSize;

  const Studio3DButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.variant = StudioButtonVariant.gold,
    this.expand = false,
    this.shimmer = true,
    this.padding,
    this.fontSize = 15,
  });

  @override
  State<Studio3DButton> createState() => _Studio3DButtonState();
}

class _Studio3DButtonState extends State<Studio3DButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _sheen = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSheen();
  }

  @override
  void didUpdateWidget(covariant Studio3DButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSheen();
  }

  void _syncSheen() {
    if (!widget.shimmer ||
        widget.onPressed == null ||
        MediaQuery.disableAnimationsOf(context)) {
      _sheen.stop();
    } else if (!_sheen.isAnimating) {
      _sheen.repeat();
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final (top, bottom, ledge, border, fg, glow) = switch (widget.variant) {
      StudioButtonVariant.gold => (
        StudioPalette.goldBright,
        const Color(0xFFE0A422),
        const Color(0xFF7D5308),
        const Color(0xFFFFF1BA),
        StudioPalette.night,
        StudioPalette.gold,
      ),
      StudioButtonVariant.navy => (
        StudioPalette.navyLight,
        const Color(0xFF0A1354),
        const Color(0xFF030620),
        StudioPalette.gold,
        Colors.white,
        StudioPalette.gold,
      ),
      StudioButtonVariant.emerald => (
        const Color(0xFF39D972),
        const Color(0xFF15873D),
        const Color(0xFF0A4D22),
        const Color(0xFFB5F7CC),
        Colors.white,
        StudioPalette.emerald,
      ),
      StudioButtonVariant.amber => (
        const Color(0xFFFFBC42),
        const Color(0xFFD96D07),
        const Color(0xFF7D3B03),
        const Color(0xFFFFE5A8),
        StudioPalette.night,
        StudioPalette.amber,
      ),
      StudioButtonVariant.crimson => (
        const Color(0xFFFF5967),
        const Color(0xFFB01E2B),
        const Color(0xFF630D15),
        const Color(0xFFFFB5BC),
        Colors.white,
        StudioPalette.crimson,
      ),
    };

    const radius = 18.0;
    const lip = 4.5;
    final pressShift = _down && enabled ? 3.5 : 0.0;
    final pad = widget.padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 13);

    Widget content = Listener(
      onPointerDown: enabled ? (_) => setState(() => _down = true) : null,
      onPointerUp: enabled ? (_) => setState(() => _down = false) : null,
      onPointerCancel: enabled ? (_) => setState(() => _down = false) : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Padding(
          padding: const EdgeInsets.only(bottom: lip),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 3D Alt Çıkıntı Tabanı (Extrusion ledge)
              Positioned.fill(
                top: lip,
                bottom: -lip,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    color: ledge,
                    boxShadow: [
                      BoxShadow(
                        color: glow.withValues(alpha: enabled ? 0.34 : 0.0),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                      const BoxShadow(
                        color: Colors.black54,
                        blurRadius: 10,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                ),
              ),
              // Üst 3D Yüzey
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                transform: Matrix4.translationValues(0, pressShift, 0),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onPressed,
                    borderRadius: BorderRadius.circular(radius),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Stack(
                        children: [
                          Container(
                            width: widget.expand ? double.infinity : null,
                            padding: pad,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(radius),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [top, bottom],
                              ),
                              border: Border.all(color: border, width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (widget.icon != null) ...[
                                  Icon(widget.icon, size: widget.fontSize + 4, color: fg),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Text(
                                    widget.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: widget.fontSize,
                                      fontWeight: FontWeight.w900,
                                      color: fg,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Üst parlak cam kenar yansıması
                          Positioned(
                            top: 1.5,
                            left: 12,
                            right: 12,
                            height: 2,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                          // Kayan metalik parlama ışığı
                          if (widget.shimmer && enabled && !MediaQuery.disableAnimationsOf(context))
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedBuilder(
                                  animation: _sheen,
                                  builder: (_, _) => CustomPaint(
                                    painter: _SheenSweepPainter(_sheen.value),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return widget.expand ? SizedBox(width: double.infinity, child: content) : content;
  }
}

class _SheenSweepPainter extends CustomPainter {
  final double t;
  const _SheenSweepPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final sweepPos = (t * 2.4 - 0.5) * size.width;
    if (sweepPos < -size.width * 0.4 || sweepPos > size.width * 1.4) return;
    final path = Path()
      ..moveTo(sweepPos, 0)
      ..lineTo(sweepPos + 34, 0)
      ..lineTo(sweepPos + 8, size.height)
      ..lineTo(sweepPos - 26, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.26),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(sweepPos - 26, 0, 60, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant _SheenSweepPainter old) => old.t != t;
}

/// Zirve Merdiveni'nin imzası olan altıgen/elmas uçlu 3D altın çerçeveli stüdyo plaketi.
class StudioHexClipper extends CustomClipper<Path> {
  final double chamfer;
  const StudioHexClipper({this.chamfer = 16});

  @override
  Path getClip(Size s) {
    final c = min(chamfer, min(s.height * 0.46, s.width * 0.14));
    final midY = s.height * 0.5;
    return Path()
      ..moveTo(c, 0)
      ..lineTo(s.width - c, 0)
      ..lineTo(s.width, midY)
      ..lineTo(s.width - c, s.height)
      ..lineTo(c, s.height)
      ..lineTo(0, midY)
      ..close();
  }

  @override
  bool shouldReclip(covariant StudioHexClipper old) => old.chamfer != chamfer;
}

class _StudioHexBorderPainter extends CustomPainter {
  final double chamfer;
  final Color borderColor;
  final double strokeWidth;
  final Color innerGloss;

  const _StudioHexBorderPainter({
    required this.chamfer,
    required this.borderColor,
    required this.strokeWidth,
    required this.innerGloss,
  });

  @override
  void paint(Canvas canvas, Size s) {
    final c = min(chamfer, min(s.height * 0.46, s.width * 0.14));
    final midY = s.height * 0.5;
    final path = Path()
      ..moveTo(c, 1)
      ..lineTo(s.width - c, 1)
      ..lineTo(s.width - 1, midY)
      ..lineTo(s.width - c, s.height - 1)
      ..lineTo(c, s.height - 1)
      ..lineTo(1, midY)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(borderColor, Colors.white, 0.35)!,
            borderColor,
            Color.lerp(borderColor, Colors.black, 0.28)!,
          ],
        ).createShader(Offset.zero & s),
    );

    // Üst iç cam yansıma çizgisi
    canvas.drawLine(
      Offset(c + 8, 3.2),
      Offset(s.width - c - 8, 3.2),
      Paint()
        ..strokeWidth = 1.1
        ..color = innerGloss,
    );
  }

  @override
  bool shouldRepaint(covariant _StudioHexBorderPainter old) =>
      old.borderColor != borderColor || old.strokeWidth != strokeWidth || old.chamfer != chamfer;
}

/// Zirve Merdiveni tarzı 3D elmas-altıgen soru / bilgi plaketi.
class Studio3DPlaque extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;
  final List<Color>? gradient;
  final double chamfer;
  final Color? glowColor;

  const Studio3DPlaque({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 16, 22, 18),
    this.borderColor = StudioPalette.gold,
    this.gradient,
    this.chamfer = 16,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final glow = glowColor ?? borderColor;
    final colors = gradient ??
        const [
          Color(0xF51D2F9A),
          Color(0xF20C165A),
          Color(0xF5050A2B),
        ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.24),
            blurRadius: 20,
            spreadRadius: 0.5,
          ),
          const BoxShadow(
            color: Color(0xCC010310),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: _StudioHexBorderPainter(
          chamfer: chamfer,
          borderColor: borderColor,
          strokeWidth: 2.2,
          innerGloss: Colors.white.withValues(alpha: 0.28),
        ),
        child: ClipPath(
          clipper: StudioHexClipper(chamfer: chamfer),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

enum StudioOptionState { normal, selected, correct, wrong, hidden }

/// Zirve Merdiveni & Standart Quiz için ortak 3D altıgen-bevel şık plaketi.
class Studio3DOptionPlaque extends StatelessWidget {
  final String letter;
  final String text;
  final StudioOptionState state;
  final VoidCallback? onTap;
  final double fontSize;
  final String? semanticsLabel;

  const Studio3DOptionPlaque({
    super.key,
    required this.letter,
    required this.text,
    required this.state,
    this.onTap,
    this.fontSize = 15.5,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final (top, bottom, border, badgeBg, badgeFg, glow) = switch (state) {
      StudioOptionState.selected => (
        const Color(0xFFFFB73B),
        const Color(0xFFCC6804),
        Colors.white,
        StudioPalette.night,
        StudioPalette.goldBright,
        StudioPalette.amber,
      ),
      StudioOptionState.correct => (
        const Color(0xFF34D16C),
        const Color(0xFF137D3A),
        const Color(0xFFD5FFE2),
        const Color(0xFF073A1B),
        const Color(0xFFD5FFE2),
        StudioPalette.emerald,
      ),
      StudioOptionState.wrong => (
        const Color(0xFFFF5563),
        const Color(0xFF9F1926),
        const Color(0xFFFFCDD2),
        const Color(0xFF4F0911),
        Colors.white,
        StudioPalette.crimson,
      ),
      StudioOptionState.hidden => (
        const Color(0x99070B2A),
        const Color(0x9904071D),
        const Color(0x44F2C14E),
        const Color(0x33F2C14E),
        Colors.white38,
        Colors.transparent,
      ),
      StudioOptionState.normal => (
        const Color(0xF0172782),
        const Color(0xF0081047),
        StudioPalette.gold,
        const Color(0x33F2C14E),
        StudioPalette.goldBright,
        StudioPalette.gold,
      ),
    };

    final disabled = state == StudioOptionState.hidden || onTap == null;
    final plaque = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: state == StudioOptionState.hidden
            ? null
            : [
                BoxShadow(
                  color: glow.withValues(
                    alpha: state == StudioOptionState.normal ? 0.16 : 0.55,
                  ),
                  blurRadius: state == StudioOptionState.normal ? 12 : 20,
                  offset: const Offset(0, 2),
                ),
                const BoxShadow(
                  color: Color(0xBF020412),
                  blurRadius: 6,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: CustomPaint(
        foregroundPainter: _StudioHexBorderPainter(
          chamfer: 14,
          borderColor: border,
          strokeWidth: state == StudioOptionState.normal ? 1.8 : 2.3,
          innerGloss: Colors.white.withValues(alpha: state == StudioOptionState.hidden ? 0.06 : 0.24),
        ),
        child: ClipPath(
          clipper: const StudioHexClipper(chamfer: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, bottom],
              ),
            ),
            child: Row(
              children: [
                // Elmas/Altın Şık Harf Rozeti
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: badgeBg,
                    border: Border.all(
                      color: state == StudioOptionState.normal
                          ? StudioPalette.gold.withValues(alpha: 0.8)
                          : Colors.white70,
                      width: 1.3,
                    ),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(
                      color: badgeFg,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: state == StudioOptionState.hidden ? Colors.white38 : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: fontSize,
                      height: 1.25,
                    ),
                  ),
                ),
                if (state == StudioOptionState.correct)
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 21)
                else if (state == StudioOptionState.wrong)
                  const Icon(Icons.cancel_rounded, color: Colors.white, size: 21),
              ],
            ),
          ),
        ),
      ),
    );

    final wrapped = disabled
        ? plaque
        : ArenaPressDepth(
            depthOffset: 2.4,
            child: GestureDetector(onTap: onTap, child: plaque),
          );

    return Semantics(
      container: true,
      excludeSemantics: state == StudioOptionState.hidden,
      button: state != StudioOptionState.hidden,
      label: semanticsLabel ??
          (state == StudioOptionState.hidden
              ? 'Seçenek $letter elendi'
              : 'Seçenek $letter: $text'),
      child: wrapped,
    );
  }
}

/// Zirve Merdiveni & Quiz için 3D metalik joker kapsülü.
class Studio3DJokerOrb extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool used;
  final VoidCallback onTap;

  const Studio3DJokerOrb({
    super.key,
    required this.icon,
    required this.label,
    required this.used,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final orb = Opacity(
      opacity: used ? 0.34 : 1.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: used ? StudioPalette.gold.withValues(alpha: 0.4) : StudioPalette.gold,
                width: 1.9,
              ),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [StudioPalette.navyLight, StudioPalette.navyDark],
              ),
              boxShadow: used
                  ? null
                  : [
                      BoxShadow(
                        color: StudioPalette.gold.withValues(alpha: 0.28),
                        blurRadius: 10,
                      ),
                      const BoxShadow(
                        color: Color(0xCC020412),
                        offset: Offset(0, 3.5),
                      ),
                    ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 2,
                  left: 10,
                  right: 10,
                  height: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: Colors.white.withValues(alpha: 0.32),
                    ),
                  ),
                ),
                Icon(icon, color: StudioPalette.goldBright, size: 20),
                if (used)
                  const Icon(Icons.close_rounded, color: StudioPalette.crimson, size: 32),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Semantics(
        button: true,
        enabled: !used,
        label: 'Joker: $label${used ? ', kullanıldı' : ''}',
        child: used
            ? orb
            : ArenaPressDepth(
                depthOffset: 2.0,
                child: GestureDetector(onTap: onTap, child: orb),
              ),
      ),
    );
  }
}

/// 3D yörüngeli altın stüdyo amblemi (Zirve girişi, kupa ve zafer sahneleri için).
class Studio3DOrbitEmblem extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color accent;
  const Studio3DOrbitEmblem({
    super.key,
    required this.icon,
    this.size = 92,
    this.accent = StudioPalette.gold,
  });

  @override
  State<Studio3DOrbitEmblem> createState() => _Studio3DOrbitEmblemState();
}

class _Studio3DOrbitEmblemState extends State<Studio3DOrbitEmblem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
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
    final animate = !MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: widget.size + 28,
      height: widget.size + 28,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final a = animate ? _ctrl.value * 2 * pi : 0.0;
          final bob = animate ? sin(a) * 3.5 : 0.0;
          final rotY = animate ? sin(a) * 0.22 : 0.0;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateY(rotY)
              ..translateByDouble(0.0, bob, 0.0, 1.0),
            child: child,
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Dış 3D altın halka parıltısı
            Container(
              width: widget.size + 18,
              height: widget.size + 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: widget.accent.withValues(alpha: 0.35), width: 1.5),
                gradient: RadialGradient(
                  colors: [
                    widget.accent.withValues(alpha: 0.24),
                    widget.accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            // İç 3D metalik madalyon
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [StudioPalette.navyLight, StudioPalette.navyMid, StudioPalette.night],
                ),
                border: Border.all(color: widget.accent, width: 2.6),
                boxShadow: [
                  BoxShadow(color: widget.accent.withValues(alpha: 0.42), blurRadius: 22),
                  const BoxShadow(color: Colors.black54, offset: Offset(0, 6), blurRadius: 12),
                ],
              ),
              child: Icon(widget.icon, color: StudioPalette.goldBright, size: widget.size * 0.54),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tüm uygulama genelinde kullanılan Zirve Merdiveni 3D lacivert-altın stüdyo kartı.
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
    final accent = tint ?? StudioPalette.gold;
    final rimColor = Color.lerp(accent, StudioPalette.gold, 0.38)!;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highContrast
              ? const [Color(0xF50E1752), Color(0xF8040822)]
              : [
                  Color.alphaBlend(accent.withValues(alpha: 0.14), const Color(0xEB162376)),
                  const Color(0xE80A1247),
                  const Color(0xEE040824),
                ],
        ),
        border: Border.all(
          color: highContrast
              ? rimColor.withValues(alpha: 0.85)
              : rimColor.withValues(alpha: 0.46),
          width: highContrast ? 1.8 : 1.35,
        ),
        boxShadow: [
          // 3D alt derinlik tabanı
          BoxShadow(
            color: Color.lerp(rimColor, const Color(0xFF010310), 0.78)!,
            offset: const Offset(0, 4.5),
          ),
          BoxShadow(
            color: rimColor.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return ArenaPressDepth(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: box,
        ),
      ),
    );
  }
}

/// 3D altın çerçeveli, İstanbul / stüdyo görselli eylem kartı.
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
    this.height = 118,
  });

  @override
  Widget build(BuildContext context) {
    final rim = Color.lerp(accent, StudioPalette.gold, 0.45)!;
    return ArenaPressDepth(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: rim.withValues(alpha: 0.72), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Color.lerp(rim, Colors.black, 0.75)!,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: rim.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20.5),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    imageAsset,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => const ColoredBox(color: StudioPalette.navyMid),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          StudioPalette.navyMid.withValues(alpha: 0.36),
                          const Color(0xBF070F3B),
                          const Color(0xF003061C),
                        ],
                      ),
                    ),
                  ),
                  // Üst altın parlama şeridi
                  Positioned(
                    top: 0,
                    left: 16,
                    right: 16,
                    height: 1.6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            StudioPalette.goldBright.withValues(alpha: 0.65),
                            Colors.transparent,
                          ],
                        ),
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
                              padding: const EdgeInsets.all(6.5),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    StudioPalette.navyLight.withValues(alpha: 0.92),
                                    StudioPalette.night.withValues(alpha: 0.92),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(color: rim.withValues(alpha: 0.8), width: 1.2),
                                boxShadow: [
                                  BoxShadow(color: rim.withValues(alpha: 0.3), blurRadius: 8),
                                ],
                              ),
                              child: Icon(icon, size: 16, color: StudioPalette.goldBright),
                            ),
                            const Spacer(),
                            if (badge != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      StudioPalette.navyTop.withValues(alpha: 0.92),
                                      StudioPalette.night.withValues(alpha: 0.92),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(color: rim.withValues(alpha: 0.7)),
                                ),
                                child: Text(
                                  badge!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    color: StudioPalette.goldBright,
                                    letterSpacing: 0.4,
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
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.2,
                            shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.84),
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
      ),
    );
  }
}

/// Zirve Merdiveni 3D kabartmalı hap seçici.
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
    final activeTone = Color.lerp(accent, StudioPalette.gold, 0.5)!;
    return ArenaPressDepth(
      depthOffset: 1.8,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(item),
          borderRadius: BorderRadius.circular(99),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isSel
                    ? [StudioPalette.goldBright, activeTone]
                    : [const Color(0xEB1A2A88), const Color(0xEB081042)],
              ),
              border: Border.all(
                color: isSel
                    ? const Color(0xFFFFF3C4)
                    : StudioPalette.gold.withValues(alpha: 0.34),
                width: isSel ? 1.5 : 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSel
                      ? activeTone.withValues(alpha: 0.35)
                      : const Color(0xAA020412),
                  blurRadius: isSel ? 10 : 4,
                  offset: const Offset(0, 2.5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 15,
                    color: isSel ? StudioPalette.night : StudioPalette.goldBright,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  labelBuilder(item),
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSel ? FontWeight.w900 : FontWeight.w700,
                    color: isSel ? StudioPalette.night : Colors.white.withValues(alpha: 0.92),
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

/// 3D altın madalyon seviye rozeti.
class LevelMedallion extends StatelessWidget {
  final int level;
  final Color gold;

  const LevelMedallion({
    super.key,
    required this.level,
    this.gold = StudioPalette.gold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [StudioPalette.navyLight, StudioPalette.navyMid, StudioPalette.night],
        ),
        border: Border.all(color: StudioPalette.gold, width: 2.0),
        boxShadow: [
          BoxShadow(color: StudioPalette.gold.withValues(alpha: 0.35), blurRadius: 12),
          const BoxShadow(color: Colors.black54, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 11, color: StudioPalette.goldBright),
          Text(
            '$level',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: StudioPalette.goldBright,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

/// Zirve Merdiveni tarzı 3D altın halka geri sayım göstergesi.
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
          gradient: const LinearGradient(
            colors: [StudioPalette.navyTop, StudioPalette.navyDark],
          ),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.65), width: 1.4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.all_inclusive_rounded, size: 15, color: StudioPalette.goldBright),
            SizedBox(width: 5),
            Text(
              'Süresiz',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: StudioPalette.goldBright,
              ),
            ),
          ],
        ),
      );
    }
    final ratio = (remainingSeconds / totalSeconds).clamp(0.0, 1.0);
    final urgent = remainingSeconds <= 5;
    final color = urgent ? StudioPalette.crimson : StudioPalette.gold;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [StudioPalette.navyTop, StudioPalette.night],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: urgent ? 0.55 : 0.28),
            blurRadius: urgent ? 14 : 10,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              value: ratio,
              strokeWidth: 4.2,
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            '$remainingSeconds',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: urgent ? const Color(0xFFFF8591) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// 3D dönen altın ve safir konfeti kutlama katmanı.
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
      duration: const Duration(milliseconds: 3000),
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
    if (!widget.active || MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
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
  const _ConfettiPainter(this.t);

  static const _colors = [
    StudioPalette.goldBright,
    StudioPalette.gold,
    StudioPalette.sapphire,
    Color(0xFF4CE0D2),
    StudioPalette.amber,
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final fade = (1.0 - t).clamp(0.0, 1.0);
    for (var i = 0; i < 54; i++) {
      final seedX = ((i * 73 + 17) % 100) / 100.0;
      final speed = 0.55 + (i % 5) * 0.16;
      final sway = sin(t * 9 + i) * 22;
      final x = seedX * size.width + sway;
      final y = -20 + t * size.height * speed * 1.18;
      // 3D takla simülasyonu: yüksekliği sinüsle sıkıştır
      final flipScale = (0.25 + 0.75 * cos(t * 14 + i * 0.9).abs());
      final paint = Paint()
        ..color = _colors[i % _colors.length].withValues(alpha: fade * 0.92);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 7 + i * 0.55);
      canvas.scale(1.0, flipScale);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-4.5, -2.8, 9, 5.6),
          const Radius.circular(1.8),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}

/// Sekme üstlerinde kullanılan 3D altın çerçeveli İstanbul sahne başlığı.
class ArenaSceneHeader extends StatelessWidget {
  final String title;
  final String description;
  final String scene;
  const ArenaSceneHeader({
    super.key,
    required this.title,
    required this.description,
    required this.scene,
  });

  String get _istanbulAsset => switch (scene) {
        'academy' => 'assets/images/istanbul_ayasofya.webp',
        'notebook' => 'assets/images/istanbul_dolmabahce.webp',
        'cyber_arena' => 'assets/images/istanbul_skyline.webp',
        'duel_stage' => 'assets/images/istanbul_suleymaniye.webp',
        'atrium' => 'assets/images/istanbul_ortakoy.webp',
        'galata' => 'assets/images/istanbul_galata.webp',
        'kiz_kulesi' => 'assets/images/istanbul_kiz_kulesi.webp',
        _ => 'assets/images/istanbul_ortakoy.webp',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: StudioPalette.gold.withValues(alpha: 0.72), width: 1.7),
        boxShadow: [
          BoxShadow(color: StudioPalette.gold.withValues(alpha: 0.22), blurRadius: 18),
          const BoxShadow(color: Color(0xD9020412), offset: Offset(0, 5), blurRadius: 12),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22.5),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                _istanbulAsset,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.25),
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const ColoredBox(color: StudioPalette.navyMid),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xEE040826),
                      const Color(0xC2091248),
                      const Color(0x660B1450),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 2.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      StudioPalette.gold.withValues(alpha: 0.0),
                      StudioPalette.goldBright,
                      StudioPalette.gold.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: StudioPalette.goldBright, size: 15),
                      const SizedBox(width: 6),
                      const Text(
                        'İSTANBUL ZİRVE STÜDYOSU',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: StudioPalette.goldBright,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.3,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.86),
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
