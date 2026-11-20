import 'package:flutter/material.dart';

/// Kâğıt uygulamasının editoryal kâğıt (Açık) ve mürekkep (Koyu) teması.
class KagitTema {
  KagitTema._();

  static const Color vurgu = Color(0xFFDB3D33);
  static const Color vurguKoyu = Color(0xFFB32920);
  static const Color altinMuhur = Color(0xFFD98E26);
  static const Color yaprakYesili = Color(0xFF288557);
  static const Color murekkepMavi = Color(0xFF2F64B8);
  static const Color morOkuma = Color(0xFF7B4EC2);
  static const Color camYesili = Color(0xFF1F877D);

  static const Color kagitZemin = Color(0xFFFAF7F0);
  static const Color kagitKart = Color(0xFFFFFFFF);
  static const Color kagitYuzey2 = Color(0xFFF1ECE1);
  static const Color kagitCizgi = Color(0xFFE3DBCC);
  static const Color koyuMurekkep = Color(0xFF1B1917);
  static const Color ikincilMurekkep = Color(0xFF6B655D);

  static const Color geceZemin = Color(0xFF141210);
  static const Color geceKart = Color(0xFF1F1B18);
  static const Color geceYuzey2 = Color(0xFF2B2622);
  static const Color geceCizgi = Color(0xFF3A332D);
  static const Color geceYazi = Color(0xFFF4EFE6);
  static const Color geceIkincil = Color(0xFFA99F94);

  static ThemeData acikTema() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'NotoSans',
      colorScheme: ColorScheme.fromSeed(
        seedColor: vurgu,
        primary: vurgu,
        secondary: altinMuhur,
        surface: kagitKart,
        brightness: Brightness.light,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: kagitZemin,
      cardColor: kagitKart,
      dividerColor: kagitCizgi,
      appBarTheme: const AppBarTheme(
        backgroundColor: kagitZemin,
        foregroundColor: koyuMurekkep,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: kagitKart,
        indicatorColor: vurgu.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'NotoSans',
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? vurgu : ikincilMurekkep,
          );
        }),
      ),
    );
  }

  static ThemeData koyuTema() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'NotoSans',
      colorScheme: ColorScheme.fromSeed(
        seedColor: vurgu,
        primary: const Color(0xFFFF685F),
        secondary: altinMuhur,
        surface: geceKart,
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: geceZemin,
      cardColor: geceKart,
      dividerColor: geceCizgi,
      appBarTheme: const AppBarTheme(
        backgroundColor: geceZemin,
        foregroundColor: geceYazi,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: geceKart,
        indicatorColor: const Color(0xFFFF685F).withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'NotoSans',
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFFFF7A72) : geceIkincil,
          );
        }),
      ),
    );
  }

  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  static Color cardBg(BuildContext context) => isDark(context) ? geceKart : kagitKart;
  static Color softBg(BuildContext context) => isDark(context) ? geceYuzey2 : kagitYuzey2;
  static Color border(BuildContext context) => isDark(context) ? geceCizgi : kagitCizgi;
  static Color inkPrimary(BuildContext context) => isDark(context) ? geceYazi : koyuMurekkep;
  static Color inkSecondary(BuildContext context) => isDark(context) ? geceIkincil : ikincilMurekkep;
}

TextStyle kagitSerif(BuildContext context, {double size = 20, FontWeight weight = FontWeight.w700, Color? color}) {
  return TextStyle(
    fontFamily: 'NotoSerif',
    fontSize: size,
    fontWeight: weight,
    color: color ?? KagitTema.inkPrimary(context),
    letterSpacing: -0.2,
  );
}

/// İnce animasyonlu editoryal hero kartı: illüstrasyon görseli, nefes alan mühür rozeti ve başlık.
class KagitHeroBanner extends StatefulWidget {
  const KagitHeroBanner({
    super.key,
    required this.imageAsset,
    required this.badge,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.bottomWidget,
    this.accent = KagitTema.vurgu,
  });

  final String imageAsset;
  final String badge;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? bottomWidget;
  final Color accent;

  @override
  State<KagitHeroBanner> createState() => _KagitHeroBannerState();
}

class _KagitHeroBannerState extends State<KagitHeroBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final zoom = 1.0 + _pulse.value * 0.05;
          final shiftX = (_pulse.value - 0.5) * 8;
          return Stack(
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(shiftX, 0),
                  child: Transform.scale(
                    scale: zoom,
                    child: Image.asset(
                      widget.imageAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [widget.accent, widget.accent.withValues(alpha: 0.72)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1A1412).withValues(alpha: 0.84),
                        const Color(0xFF1F1614).withValues(alpha: 0.62),
                        widget.accent.withValues(alpha: 0.48),
                      ],
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
              const SizedBox(height: 14),
              Text(
                widget.title,
                style: const TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.35,
                ),
              ),
              if (widget.bottomWidget != null) ...[
                const SizedBox(height: 14),
                widget.bottomWidget!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Türkçe dosya boyutu biçimlendirici.
String formatFileSizeTr(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// Türkçe göreli zaman etiketi.
String formatRelativeDateTr(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Az önce';
  if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
  if (diff.inDays < 1) return '${diff.inHours} sa önce';
  if (diff.inDays == 1) return 'Dün';
  if (diff.inDays < 7) return '${diff.inDays} gün önce';
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}
