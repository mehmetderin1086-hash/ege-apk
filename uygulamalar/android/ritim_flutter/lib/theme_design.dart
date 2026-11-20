import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Ritim'in 6 görsel teması (iPhone DesignSystem eşleniği + geliştirilmiş cam efektleri).
enum RitimThemeStyle {
  nane('nane', 'Nane', 'Klasik karanlık & nane', Icons.waves_rounded),
  okyanus('okyanus', 'Okyanus', 'Derin lacivert & buz', Icons.water_drop_rounded),
  gunbatimi('gunbatimi', 'Gün batımı', 'Kızıl, kehribar & sıcak', Icons.wb_twilight_rounded),
  orman('orman', 'Orman', 'Zümrüt & gece yeşili', Icons.forest_rounded),
  gul('gul', 'Gül', 'Patlıcan & pembe altın', Icons.local_florist_rounded),
  rengarenk('rengarenk', 'Rengârenk', 'Spektrum & prizma', Icons.auto_awesome_rounded);

  const RitimThemeStyle(this.id, this.title, this.subtitle, this.icon);

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  static RitimThemeStyle fromId(String? id) {
    return RitimThemeStyle.values.firstWhere(
      (e) => e.id == id,
      orElse: () => RitimThemeStyle.nane,
    );
  }
}

/// Ritim ekranları için seçilebilir tam ekran stüdyo ve atmosfer duvar kâğıtları.
enum RitimWallpaper {
  studio(
    'studio',
    'Stüdyo Spektrum',
    'Mikser masası & neon ses dalgaları',
    'assets/images/ritim_download_studio.jpg',
    Icons.graphic_eq_rounded,
  ),
  nightDrive(
    'night_drive',
    'Gece Sürüşü',
    'Yağmurlu gece köprüsü & şehir ışıkları',
    'assets/images/ritim_night_drive_bg.jpg',
    Icons.nights_stay_rounded,
  ),
  concertStage(
    'concert_stage',
    'Konser Sahnesi',
    'Akustik mikrofon & altın sahne spotları',
    'assets/images/ritim_search_stage.jpg',
    Icons.mic_external_on_rounded,
  ),
  vinylRoom(
    'vinyl_room',
    'Plak & Amfi',
    'Lambalı amfi & sıcak plak koleksiyonu',
    'assets/images/ritim_library_vinyl.jpg',
    Icons.album_rounded,
  ),
  aiDeck(
    'ai_deck',
    'Holografik DJ',
    'Biyolüminesan pikap & ses prizması',
    'assets/images/ritim_ai_dj_deck.jpg',
    Icons.auto_awesome_rounded,
  ),
  lounge(
    'lounge',
    'Gece Salonu',
    'Lo-Fi dinleme köşesi & yumuşak ışık',
    'assets/images/ritim_lounge_backdrop.jpg',
    Icons.weekend_rounded,
  ),
  minimal(
    'minimal',
    'Saf Karanlık',
    'Yalnızca canlı ses dalgaları & aurora',
    null,
    Icons.dark_mode_rounded,
  );

  const RitimWallpaper(
    this.id,
    this.title,
    this.subtitle,
    this.assetPath,
    this.icon,
  );

  final String id;
  final String title;
  final String subtitle;
  final String? assetPath;
  final IconData icon;

  static RitimWallpaper fromId(String? id) {
    return RitimWallpaper.values.firstWhere(
      (e) => e.id == id,
      orElse: () => RitimWallpaper.studio,
    );
  }
}

class RitimPalette {
  const RitimPalette({
    required this.style,
    required this.background,
    required this.surface,
    required this.elevated,
    required this.primary,
    required this.secondary,
    required this.coral,
    required this.muted,
    required this.coverPalettes,
  });

  final RitimThemeStyle style;
  final Color background;
  final Color surface;
  final Color elevated;
  final Color primary;
  final Color secondary;
  final Color coral;
  final Color muted;
  final List<(Color, Color)> coverPalettes;

  static RitimPalette of(RitimThemeStyle style) {
    switch (style) {
      case RitimThemeStyle.nane:
        return const RitimPalette(
          style: RitimThemeStyle.nane,
          background: Color(0xFF0A0A0D),
          surface: Color(0xFF14141A),
          elevated: Color(0xFF1E1E26),
          primary: Color(0xFF70F5C0),
          secondary: Color(0xFF948EFF),
          coral: Color(0xFFFF7A70),
          muted: Color(0xFF8C8C99),
          coverPalettes: [
            (Color(0xFF124D40), Color(0xFF70F5C0)),
            (Color(0xFF2B2161), Color(0xFF948EFF)),
            (Color(0xFF66242E), Color(0xFFFF7A70)),
            (Color(0xFF174561), Color(0xFF5EEAD4)),
            (Color(0xFF4F381C), Color(0xFFFFB56B)),
            (Color(0xFF421C59), Color(0xFFE07DFF)),
          ],
        );
      case RitimThemeStyle.okyanus:
        return const RitimPalette(
          style: RitimThemeStyle.okyanus,
          background: Color(0xFF050A14),
          surface: Color(0xFF0D1424),
          elevated: Color(0xFF142138),
          primary: Color(0xFF38DDFC),
          secondary: Color(0xFF5C8FFF),
          coral: Color(0xFFFF8C6E),
          muted: Color(0xFF8797B5),
          coverPalettes: [
            (Color(0xFF0A335C), Color(0xFF38DDFC)),
            (Color(0xFF142661), Color(0xFF5C8FFF)),
            (Color(0xFF0A4D57), Color(0xFF66F2E0)),
            (Color(0xFF261E5C), Color(0xFF9E8CFF)),
            (Color(0xFF0F384A), Color(0xFF8CD9FA)),
            (Color(0xFF332154), Color(0xFFFF8C9E)),
          ],
        );
      case RitimThemeStyle.gunbatimi:
        return const RitimPalette(
          style: RitimThemeStyle.gunbatimi,
          background: Color(0xFF140A0D),
          surface: Color(0xFF1E1217),
          elevated: Color(0xFF2B1A21),
          primary: Color(0xFFFFAD5C),
          secondary: Color(0xFFFF667D),
          coral: Color(0xFFFFD67A),
          muted: Color(0xFFA88F94),
          coverPalettes: [
            (Color(0xFF591F2E), Color(0xFFFFAD5C)),
            (Color(0xFF611C33), Color(0xFFFF667D)),
            (Color(0xFF543017), Color(0xFFFFD67A)),
            (Color(0xFF471C4D), Color(0xFFFA85AD)),
            (Color(0xFF66291A), Color(0xFFFF9961)),
            (Color(0xFF4A173B), Color(0xFFF575C2)),
          ],
        );
      case RitimThemeStyle.orman:
        return const RitimPalette(
          style: RitimThemeStyle.orman,
          background: Color(0xFF050F0A),
          surface: Color(0xFF0D1C14),
          elevated: Color(0xFF142B1F),
          primary: Color(0xFF52F599),
          secondary: Color(0xFFBAE87D),
          coral: Color(0xFFFCA866),
          muted: Color(0xFF859C8F),
          coverPalettes: [
            (Color(0xFF0F4026), Color(0xFF52F599)),
            (Color(0xFF1F471C), Color(0xFFBAE87D)),
            (Color(0xFF0F4738), Color(0xFF5EE8C7)),
            (Color(0xFF36421C), Color(0xFFE0ED85)),
            (Color(0xFF123B29), Color(0xFF7DF0AD)),
            (Color(0xFF3B3617), Color(0xFFFCA866)),
          ],
        );
      case RitimThemeStyle.gul:
        return const RitimPalette(
          style: RitimThemeStyle.gul,
          background: Color(0xFF120812),
          surface: Color(0xFF1C0F1C),
          elevated: Color(0xFF291729),
          primary: Color(0xFFFF82B2),
          secondary: Color(0xFFD699FF),
          coral: Color(0xFFFFB59E),
          muted: Color(0xFFA68CA6),
          coverPalettes: [
            (Color(0xFF4F1736), Color(0xFFFF82B2)),
            (Color(0xFF3B1A54), Color(0xFFD699FF)),
            (Color(0xFF572429), Color(0xFFFFB59E)),
            (Color(0xFF471C42), Color(0xFFFF9ED4)),
            (Color(0xFF361F59), Color(0xFFBFA8FF)),
            (Color(0xFF5C1F33), Color(0xFFFF9485)),
          ],
        );
      case RitimThemeStyle.rengarenk:
        return const RitimPalette(
          style: RitimThemeStyle.rengarenk,
          background: Color(0xFF0A0812),
          surface: Color(0xFF141221),
          elevated: Color(0xFF1F1C33),
          primary: Color(0xFFFF7A99),
          secondary: Color(0xFF6BE8FF),
          coral: Color(0xFFFFC759),
          muted: Color(0xFF9494AB),
          coverPalettes: [
            (Color(0xFF52124D), Color(0xFFFF7A99)),
            (Color(0xFF123366), Color(0xFF6BE8FF)),
            (Color(0xFF59330D), Color(0xFFFFC759)),
            (Color(0xFF124F42), Color(0xFF52F5AD)),
            (Color(0xFF381C66), Color(0xFFCC85FF)),
            (Color(0xFF5E172E), Color(0xFFFF8F6E)),
          ],
        );
    }
  }

  ThemeData toThemeData() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        tertiary: coral,
        surface: surface,
        onSurface: Colors.white,
        onPrimary: background,
      ),
      cardColor: surface,
      dividerColor: Colors.white.withValues(alpha: 0.08),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevated,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
    );
  }
}

/// Ritim ekranlarında fotoğrafik duvar kâğıdı + canlı ses dalgaları + bokeh ışık parçacıkları.
class RitimAmbientBackground extends StatefulWidget {
  const RitimAmbientBackground({
    super.key,
    required this.palette,
    required this.child,
    this.isPlaying = false,
    this.wallpaper = RitimWallpaper.studio,
  });

  final RitimPalette palette;
  final Widget child;
  final bool isPlaying;
  final RitimWallpaper wallpaper;

  @override
  State<RitimAmbientBackground> createState() => _RitimAmbientBackgroundState();
}

class _RitimAmbientBackgroundState extends State<RitimAmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambientCtrl;

  @override
  void initState() {
    super.initState();
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _ambientCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final asset = widget.wallpaper.assetPath;

    return Stack(
      children: [
        Positioned.fill(child: Container(color: p.background)),
        if (asset != null)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ambientCtrl,
              builder: (_, _) {
                final breath =
                    1.0 + 0.04 * ((math.sin(_ambientCtrl.value * 2 * math.pi) + 1) / 2);
                return Transform.scale(
                  scale: breath,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: SizedBox.expand(
                      key: ValueKey(asset),
                      child: Opacity(
                        opacity: widget.isPlaying ? 0.36 : 0.28,
                        child: Image.asset(
                          asset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ambientCtrl,
            builder: (_, _) {
              final angle = _ambientCtrl.value * 2 * math.pi;
              final dx1 = math.cos(angle) * 36;
              final dy1 = math.sin(angle) * 28;
              final dx2 = math.sin(angle * 1.3) * 42;
              final dy2 = math.cos(angle * 0.9) * 32;
              return Stack(
                children: [
                  Positioned(
                    top: -95 + dy1,
                    left: -65 + dx1,
                    child: Container(
                      width: 330,
                      height: 330,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            p.primary.withValues(
                                alpha: widget.isPlaying ? 0.28 : 0.18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 190 + dy2,
                    right: -85 + dx2,
                    child: Container(
                      width: 290,
                      height: 290,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            p.secondary.withValues(
                                alpha: widget.isPlaying ? 0.24 : 0.16),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 80 - dy1,
                    left: -50 - dx2 * 0.5,
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            p.coral.withValues(
                                alpha: widget.isPlaying ? 0.16 : 0.09),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _RitimAuroraWavePainter(
                          progress: _ambientCtrl.value,
                          primary: p.primary,
                          secondary: p.secondary,
                          coral: p.coral,
                          isPlaying: widget.isPlaying,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    p.background.withValues(alpha: 0.42),
                    p.background.withValues(alpha: 0.74),
                    p.background.withValues(alpha: 0.94),
                  ],
                  stops: const [0.0, 0.52, 0.96],
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _RitimAuroraWavePainter extends CustomPainter {
  const _RitimAuroraWavePainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.coral,
    required this.isPlaying,
  });

  final double progress;
  final Color primary;
  final Color secondary;
  final Color coral;
  final bool isPlaying;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final speedMul = isPlaying ? 2.0 : 1.0;
    final ampMul = isPlaying ? 1.45 : 0.85;
    final colors = [primary, secondary, coral];

    for (var w = 0; w < 3; w++) {
      final path = Path();
      final baseY = size.height * (0.22 + w * 0.24);
      final amp = (16.0 + w * 7.0) * ampMul;
      final phase = progress * 2 * math.pi * speedMul + w * 1.4;

      for (var x = 0.0; x <= size.width; x += 12) {
        final norm = x / size.width;
        final y = baseY +
            math.sin(norm * 3.4 * math.pi + phase) * amp +
            math.cos(norm * 1.8 * math.pi - phase * 0.7) * (amp * 0.42);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isPlaying ? 1.8 : 1.2
        ..color = colors[w].withValues(alpha: isPlaying ? 0.20 : 0.11);
      canvas.drawPath(path, paint);
    }

    // Yüzen bokeh ışık zerreleri
    for (var i = 0; i < 16; i++) {
      final seed = i * 0.61803398875;
      final fx = (seed * 7.3) % 1.0;
      final fy = (1.0 - ((progress * (0.35 + (i % 3) * 0.15) + seed) % 1.0));
      final cx = fx * size.width + math.sin(progress * 2 * math.pi + i) * 14;
      final cy = fy * size.height;
      final radius = 1.6 + (i % 4) * 1.15;
      final c = colors[i % colors.length];

      final glowPaint = Paint()
        ..color = c.withValues(alpha: isPlaying ? 0.22 : 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(cx, cy), radius * 1.8, glowPaint);

      final corePaint = Paint()
        ..color = Colors.white.withValues(alpha: isPlaying ? 0.32 : 0.18);
      canvas.drawCircle(Offset(cx, cy), radius * 0.65, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RitimAuroraWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.primary != primary;
  }
}

/// Ritim cam yüzeyi (isteğe bağlı arka plan fotoğrafı ve neon ışıma destekli).
class RitimGlassCard extends StatelessWidget {
  const RitimGlassCard({
    super.key,
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.glowColor,
    this.backgroundAsset,
    this.backgroundOpacity = 0.22,
    this.onTap,
  });

  final RitimPalette palette;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? glowColor;
  final String? backgroundAsset;
  final double backgroundOpacity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final border = glowColor?.withValues(alpha: 0.38) ??
        Colors.white.withValues(alpha: 0.10);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.surface.withValues(alpha: backgroundAsset != null ? 0.78 : 0.88),
            palette.elevated.withValues(alpha: backgroundAsset != null ? 0.70 : 0.80),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: [
          if (glowColor != null)
            BoxShadow(
              color: glowColor!.withValues(alpha: 0.18),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: child,
    );

    if (backgroundAsset != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: backgroundOpacity,
                child: Image.asset(
                  backgroundAsset!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            content,
          ],
        ),
      );
    }

    if (onTap == null) return content;
    return RitimPress(
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

/// Ritim üst vitrin / sahne afişi (Secde Vakti & Kitap Bul tarzı zengin resimli başlık kartı).
class RitimHeroBanner extends StatelessWidget {
  const RitimHeroBanner({
    super.key,
    required this.palette,
    required this.assetPath,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.icon = Icons.auto_awesome_rounded,
    this.accentColor,
    this.trailing,
    this.bottom,
  });

  final RitimPalette palette;
  final String assetPath;
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? accentColor;
  final Widget? trailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? palette.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.34)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                assetPath,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(color: palette.elevated),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      palette.background.withValues(alpha: 0.62),
                      palette.surface.withValues(alpha: 0.80),
                      palette.background.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -35,
              right: -25,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.28),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                    color: accent.withValues(alpha: 0.38)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 13, color: accent),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      eyebrow,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.80),
                                fontSize: 12.8,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 12),
                        trailing!,
                      ],
                    ],
                  ),
                  if (bottom != null) ...[
                    const SizedBox(height: 14),
                    bottom!,
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

/// Resim dokulu, neon kenarlıklı ve yay animasyonlu zengin Ritim aksiyon butonu.
class RitimImageActionButton extends StatelessWidget {
  const RitimImageActionButton({
    super.key,
    required this.palette,
    required this.assetPath,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accentColor,
    this.badge,
    this.height = 122,
  });

  final RitimPalette palette;
  final String assetPath;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? accentColor;
  final String? badge;
  final double height;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? palette.primary;
    return RitimPress(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.36)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: palette.elevated),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.background.withValues(alpha: 0.38),
                        palette.background.withValues(alpha: 0.78),
                        palette.background.withValues(alpha: 0.94),
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
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: accent.withValues(alpha: 0.45)),
                          ),
                          child: Icon(icon, color: accent, size: 18),
                        ),
                        const Spacer(),
                        if (badge != null && badge!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18)),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.2,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.74),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: accent,
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
    );
  }
}

/// Dönen plak (Vinyl LP) animasyonu — çalma sırasında 360° akıcı dönüş yapar.
class RitimSpinningVinyl extends StatefulWidget {
  const RitimSpinningVinyl({
    super.key,
    required this.palette,
    required this.isPlaying,
    this.artworkPath,
    this.colorIndex = 0,
    this.size = 92,
  });

  final RitimPalette palette;
  final bool isPlaying;
  final String? artworkPath;
  final int colorIndex;
  final double size;

  @override
  State<RitimSpinningVinyl> createState() => _RitimSpinningVinylState();
}

class _RitimSpinningVinylState extends State<RitimSpinningVinyl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    if (widget.isPlaying) _spinCtrl.repeat();
  }

  @override
  void didUpdateWidget(RitimSpinningVinyl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_spinCtrl.isAnimating) {
      _spinCtrl.repeat();
    } else if (!widget.isPlaying && _spinCtrl.isAnimating) {
      _spinCtrl.stop();
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final labelSize = s * 0.44;
    final p = widget.palette;
    final pair = p.coverPalettes[widget.colorIndex % p.coverPalettes.length];

    Widget centerArt;
    if (widget.artworkPath != null &&
        widget.artworkPath!.isNotEmpty &&
        File(widget.artworkPath!).existsSync()) {
      centerArt = Image.file(
        File(widget.artworkPath!),
        width: labelSize,
        height: labelSize,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _defaultCenter(pair, labelSize),
      );
    } else {
      centerArt = _defaultCenter(pair, labelSize);
    }

    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _spinCtrl,
        builder: (_, child) {
          return Transform.rotate(
            angle: _spinCtrl.value * 2 * math.pi,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [
                Color(0xFF2B2B34),
                Color(0xFF131318),
                Color(0xFF23232C),
                Color(0xFF0B0B0F),
              ],
              stops: [0.0, 0.45, 0.74, 1.0],
            ),
            border: Border.all(
              color: widget.isPlaying
                  ? p.primary.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.18),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: (widget.isPlaying ? p.primary : Colors.black)
                    .withValues(alpha: widget.isPlaying ? 0.28 : 0.45),
                blurRadius: widget.isPlaying ? 22 : 12,
              ),
            ],
          ),
          child: CustomPaint(
            painter: _VinylGroovesPainter(accent: p.primary),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(child: centerArt),
                  Container(
                    width: s * 0.09,
                    height: s * 0.09,
                    decoration: BoxDecoration(
                      color: p.background,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54, width: 1.2),
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

  Widget _defaultCenter((Color, Color) pair, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pair.$1, pair.$2],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: 0.9),
        size: size * 0.48,
      ),
    );
  }
}

class _VinylGroovesPainter extends CustomPainter {
  const _VinylGroovesPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = Colors.white.withValues(alpha: 0.08);

    for (final f in const [0.58, 0.68, 0.78, 0.88]) {
      canvas.drawCircle(center, maxR * f, groovePaint);
    }

    final sheenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = maxR * 0.28
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          accent.withValues(alpha: 0.14),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR * 0.74, sheenPaint);
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// Yay efektli basılabilir Ritim kartı / düğmesi.
class RitimPress extends StatefulWidget {
  const RitimPress({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<RitimPress> createState() => _RitimPressState();
}

class _RitimPressState extends State<RitimPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.962 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Canlı çalma çubuğu (Equalizer waveform).
class PlayingBars extends StatefulWidget {
  const PlayingBars({
    super.key,
    required this.isPlaying,
    required this.color,
    this.size = 24,
    this.barCount = 4,
  });

  final bool isPlaying;
  final Color color;
  final double size;
  final int barCount;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.barCount, (i) {
              final phase = (_controller.value * 2 * math.pi) + (i * 1.15);
              final factor = widget.isPlaying
                  ? (0.28 + 0.72 * ((math.sin(phase) + 1) / 2))
                  : (0.25 + (i % 2) * 0.18);
              return Container(
                width: math.max(2.5, widget.size / (widget.barCount * 2.1)),
                height: math.max(4, widget.size * factor),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/// Parça / liste kapak görseli: dosya eki, gömülü kapak veya temalı plak/gradient sanatı.
class RitimCoverArt extends StatelessWidget {
  const RitimCoverArt({
    super.key,
    required this.palette,
    required this.colorIndex,
    this.artworkPath,
    this.isVideo = false,
    this.size = 54,
    this.radius = 12,
    this.isPlaying = false,
  });

  final RitimPalette palette;
  final int colorIndex;
  final String? artworkPath;
  final bool isVideo;
  final double size;
  final double radius;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final pair = palette.coverPalettes[colorIndex % palette.coverPalettes.length];
    Widget inner;
    if (artworkPath != null &&
        artworkPath!.isNotEmpty &&
        File(artworkPath!).existsSync()) {
      inner = Image.file(
        File(artworkPath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(pair),
      );
    } else {
      inner = _fallback(pair);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        alignment: Alignment.center,
        children: [
          inner,
          if (isPlaying)
            Container(
              width: size,
              height: size,
              color: Colors.black.withValues(alpha: 0.42),
              alignment: Alignment.center,
              child: PlayingBars(
                isPlaying: true,
                color: palette.primary,
                size: math.min(28, size * 0.48),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallback((Color, Color) pair) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pair.$1, pair.$2.withValues(alpha: 0.85)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0.30,
            child: Image.asset(
              'assets/images/ritim_vinyl_cover.jpg',
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          Icon(
            isVideo ? Icons.videocam_rounded : Icons.music_note_rounded,
            color: Colors.white.withValues(alpha: 0.92),
            size: size * 0.44,
          ),
        ],
      ),
    );
  }
}

String formatDurationHuman(double seconds) {
  if (!seconds.isFinite || seconds <= 0) return '0 dk';
  final total = seconds.round();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final secs = total % 60;
  if (hours > 0) return '$hours sa $minutes dk';
  if (minutes > 0) return '$minutes dk $secs sn';
  return '$secs sn';
}

String formatClock(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '0:00';
  final total = seconds.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 KB';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
