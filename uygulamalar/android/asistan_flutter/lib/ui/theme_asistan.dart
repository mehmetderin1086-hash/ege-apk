import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class AsistanThemePreset {
  const AsistanThemePreset({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.surfaceBg,
    required this.cardBg,
    required this.defaultWallpaper,
  });

  final String id;
  final String name;
  final String subtitle;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color surfaceBg;
  final Color cardBg;
  final String defaultWallpaper;

  static const List<AsistanThemePreset> presets = [
    AsistanThemePreset(
      id: 'balanced_gray',
      name: 'Dengeli Gri',
      subtitle: 'Yumuşak gri yüzeyler ve okunaklı yazılar',
      primary: Color(0xFFB6E5DD),
      secondary: Color(0xFFCCD6F6),
      tertiary: Color(0xFFE8CBA8),
      surfaceBg: Color(0xFF555B63),
      cardBg: Color(0xFF626972),
      defaultWallpaper: 'assets/images/bg_higgsfield_technology.png',
    ),
    AsistanThemePreset(
      id: 'quantum_ocean',
      name: 'Kuantum Okyanus',
      subtitle: 'Siber camgöbeği, elektrik çivit ve derin uzay',
      primary: Color(0xFF00E5FF),
      secondary: Color(0xFF6366F1),
      tertiary: Color(0xFF38BDF8),
      surfaceBg: Color(0xFF050814),
      cardBg: Color(0xCC0D1326),
      defaultWallpaper: 'assets/images/bg_quantum_core.jpg',
    ),
    AsistanThemePreset(
      id: 'siri_aurora',
      name: 'Siri Aurora',
      subtitle: 'Apple Intelligence & Siri sıvı ışık şeritleri',
      primary: Color(0xFFFF2E93),
      secondary: Color(0xFF8B5CF6),
      tertiary: Color(0xFF00F0FF),
      surfaceBg: Color(0xFF090514),
      cardBg: Color(0xCC160C28),
      defaultWallpaper: 'assets/images/bg_aurora_nebula.jpg',
    ),
    AsistanThemePreset(
      id: 'gemini_nova',
      name: 'Gemini Yıldızı',
      subtitle: 'Google Gemini Live mavi, mor ve mercan parıltısı',
      primary: Color(0xFF4F8BFF),
      secondary: Color(0xFFC084FC),
      tertiary: Color(0xFFFF7A7A),
      surfaceBg: Color(0xFF060916),
      cardBg: Color(0xCC0F162B),
      defaultWallpaper: 'assets/images/bg_cyber_atrium.jpg',
    ),
    AsistanThemePreset(
      id: 'claude_amber',
      name: 'Claude Kehribar',
      subtitle: 'Sıcak altın, bakır ve obsidyen çalışma stüdyosu',
      primary: Color(0xFFF59E0B),
      secondary: Color(0xFFEC4899),
      tertiary: Color(0xFF34D399),
      surfaceBg: Color(0xFF0C0907),
      cardBg: Color(0xCC1C1410),
      defaultWallpaper: 'assets/images/bg_obsidian_studio.jpg',
    ),
    AsistanThemePreset(
      id: 'emerald_matrix',
      name: 'Zümrüt Kuantum',
      subtitle: 'ChatGPT zümrüt yeşili ve turkuaz nöral ağ',
      primary: Color(0xFF10B981),
      secondary: Color(0xFF06B6D4),
      tertiary: Color(0xFFA855F7),
      surfaceBg: Color(0xFF040D0B),
      cardBg: Color(0xCC0B1F1A),
      defaultWallpaper: 'assets/images/bg_quantum_core.jpg',
    ),
    AsistanThemePreset(
      id: 'crimson_nebula',
      name: 'Kızıl Nebülöz',
      subtitle: 'Yakut kırmızısı, neon macenta ve derin galaksi',
      primary: Color(0xFFF43F5E),
      secondary: Color(0xFFD946EF),
      tertiary: Color(0xFF38BDF8),
      surfaceBg: Color(0xFF11050A),
      cardBg: Color(0xCC240B16),
      defaultWallpaper: 'assets/images/bg_aurora_nebula.jpg',
    ),
  ];

  static AsistanThemePreset fromId(String? id) {
    return presets.firstWhere((e) => e.id == id, orElse: () => presets.first);
  }

  ThemeData toThemeData() {
    final scheme = ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      surface: surfaceBg,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: surfaceBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardBg.withValues(alpha: 0.95),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class WallpaperOption {
  const WallpaperOption({
    required this.assetPath,
    required this.title,
    required this.subtitle,
  });

  final String assetPath;
  final String title;
  final String subtitle;

  static const List<WallpaperOption> all = [
    WallpaperOption(
      assetPath: 'assets/images/bg_quantum_core.jpg',
      title: 'Kuantum Çekirdek',
      subtitle: 'Holografik sinir ağları ve mavi aurora',
    ),
    WallpaperOption(
      assetPath: 'assets/images/bg_aurora_nebula.jpg',
      title: 'Siri & Live Aurora',
      subtitle: 'Akışkan ipek ışık şeritleri ve macenta parıltı',
    ),
    WallpaperOption(
      assetPath: 'assets/images/bg_cyber_atrium.jpg',
      title: 'Siber Komuta Merkezi',
      subtitle: 'Yıldız ufku ve holografik cam atriyum',
    ),
    WallpaperOption(
      assetPath: 'assets/images/bg_obsidian_studio.jpg',
      title: 'Obsidyen Stüdyo',
      subtitle: 'Derin kontrastlı çalışma ve kodlama ortamı',
    ),
  ];
}

class AsistanWallpaperBackground extends StatelessWidget {
  const AsistanWallpaperBackground({
    super.key,
    required this.preset,
    required this.wallpaperAsset,
    required this.child,
    this.dimOpacity = 0.62,
  });

  final AsistanThemePreset preset;
  final String wallpaperAsset;
  final Widget child;
  final double dimOpacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: preset.surfaceBg),
        if (wallpaperAsset.isNotEmpty)
          Image.asset(
            wallpaperAsset,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                preset.surfaceBg.withValues(alpha: dimOpacity * 0.85),
                preset.surfaceBg.withValues(alpha: dimOpacity),
                preset.surfaceBg.withValues(
                  alpha: (dimOpacity + 0.22).clamp(0.0, 0.96),
                ),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class GlassCard3D extends StatefulWidget {
  const GlassCard3D({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 20,
    this.borderColor,
    this.backgroundColor,
    this.onTap,
    this.enable3DTilt = true,
    this.blurSigma = 12,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final bool enable3DTilt;
  final double blurSigma;

  @override
  State<GlassCard3D> createState() => _GlassCard3DState();
}

class _GlassCard3DState extends State<GlassCard3D> {
  double _pitch = 0.0;
  double _yaw = 0.0;

  void _updateTilt(Offset localPos, Size size) {
    if (!widget.enable3DTilt || size.width <= 0 || size.height <= 0) return;
    final dx = ((localPos.dx / size.width) - 0.5) * 2.0;
    final dy = ((localPos.dy / size.height) - 0.5) * 2.0;
    setState(() {
      _yaw = (dx * 0.10).clamp(-0.14, 0.14);
      _pitch = (-dy * 0.10).clamp(-0.14, 0.14);
    });
  }

  void _resetTilt() {
    if (_pitch == 0.0 && _yaw == 0.0) return;
    setState(() {
      _pitch = 0.0;
      _yaw = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderCol =
        widget.borderColor ?? scheme.primary.withValues(alpha: 0.28);
    final bgCol = widget.backgroundColor ?? scheme.surfaceContainerHigh;

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateX(_pitch)
      ..rotateY(_yaw);

    return Padding(
      padding: widget.margin,
      child: GestureDetector(
        onTap: widget.onTap,
        onPanDown: widget.enable3DTilt
            ? (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) _updateTilt(d.localPosition, box.size);
              }
            : null,
        onPanUpdate: widget.enable3DTilt
            ? (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) _updateTilt(d.localPosition, box.size);
              }
            : null,
        onPanEnd: widget.enable3DTilt ? (_) => _resetTilt() : null,
        onPanCancel: widget.enable3DTilt ? _resetTilt : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          transformAlignment: Alignment.center,
          transform: matrix,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: widget.blurSigma,
                sigmaY: widget.blurSigma,
              ),
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: bgCol,
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(color: borderCol, width: 1.1),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(
                        alpha:
                            0.08 + (math.max(_pitch.abs(), _yaw.abs()) * 0.5),
                      ),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
