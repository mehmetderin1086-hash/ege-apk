import 'package:flutter/material.dart';
import 'chat_palette.dart';
import 'ege_3d.dart';

/// Shared Ege design tokens and small building blocks.
class JColors {
  static Color get bg => ChatPalette.background;
  static Color get surface => ChatPalette.surface;
  static Color get surfaceHi => ChatPalette.soft;
  static Color get border => ChatPalette.border;
  static Color get primary => ChatPalette.accent;
  static Color get accent => ChatPalette.accent;
  static const violet = Color(0xFFA78BFA);
  static Color get text => ChatPalette.ink;
  static Color get muted => ChatPalette.muted;
  static Color get dim => ChatPalette.muted;
  static const ok = Color(0xFF34D399);
  static const warn = Color(0xFFFBBF24);
  static const bad = Color(0xFFF87171);
  static Color get code => ChatPalette.soft;
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? glow;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.glow,
    this.onTap,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final g = glow ?? JColors.primary;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(JColors.surfaceHi, g, 0.06)!.withValues(alpha: 0.90),
            JColors.surface.withValues(alpha: 0.88),
            JColors.surface.withValues(alpha: 0.92),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: g.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: g.withValues(alpha: 0.08),
            blurRadius: 22,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: child,
    );
    return Padding(
      padding: margin,
      child: onTap == null
          ? content
          : Tilt3D(
              maxAngle: 0.10,
              child: _Pressable(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onTap,
                    child: content,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Small press squeeze (kept local so this file has no effect dependencies).
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child});

  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Widget? trailing;

  const SectionTitle(this.text, {super.key, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: JColors.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style:  TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: JColors.accent,
                letterSpacing: 0.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  final bool? ok;
  final double size;

  const StatusDot({super.key, required this.ok, this.size = 9});

  @override
  Widget build(BuildContext context) {
    final color = ok == true
        ? JColors.ok
        : ok == false
            ? JColors.bad
            : JColors.warn;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;

  const Pill(this.text, {super.key, this.icon, this.color = const Color(0xFF1976D2)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;

  const QuickTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.color = const Color(0xFF1976D2),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tilt3D(
      maxAngle: 0.20,
      child: _Pressable(
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(JColors.surface, color, 0.10)!.withValues(alpha: 0.92),
                JColors.surface.withValues(alpha: 0.92),
              ],
            ),
            border: Border.all(color: color.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.07), blurRadius: 14),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.26),
                      color.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 10),
                    BoxShadow(
                      color: Color.lerp(color, Colors.black, 0.5)!.withValues(alpha: 0.30),
                      offset: const Offset(0, 3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:  TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: JColors.text,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(fontSize: 10.5, color: JColors.muted),
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

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'şimdi';
  if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
  if (d.inHours < 24) return '${d.inHours} sa önce';
  if (d.inDays < 30) return '${d.inDays} gün önce';
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}

IconData fileIconFor(String name, {bool isDir = false}) {
  if (isDir) return Icons.folder_rounded;
  final l = name.toLowerCase();
  if (l.endsWith('.dart')) return Icons.flutter_dash;
  if (l.endsWith('.py')) return Icons.code_rounded;
  if (l.endsWith('.kt') || l.endsWith('.java') || l.endsWith('.kts')) {
    return Icons.android_rounded;
  }
  if (l.endsWith('.md') || l.endsWith('.txt')) return Icons.article_outlined;
  if (l.endsWith('.json') || l.endsWith('.yaml') || l.endsWith('.yml')) {
    return Icons.data_object_rounded;
  }
  if (l.endsWith('.png') || l.endsWith('.jpg') || l.endsWith('.jpeg') || l.endsWith('.webp')) {
    return Icons.image_outlined;
  }
  if (l.endsWith('.apk')) return Icons.install_mobile_rounded;
  if (l.endsWith('.zip') || l.endsWith('.7z') || l.endsWith('.rar')) {
    return Icons.folder_zip_outlined;
  }
  if (l.endsWith('.ps1') || l.endsWith('.bat') || l.endsWith('.sh') || l.endsWith('.cmd')) {
    return Icons.terminal_rounded;
  }
  if (l.endsWith('.html') || l.endsWith('.css') || l.endsWith('.js') || l.endsWith('.ts') || l.endsWith('.vue')) {
    return Icons.web_rounded;
  }
  return Icons.insert_drive_file_outlined;
}

Color fileColorFor(String name, {bool isDir = false}) {
  if (isDir) return const Color(0xFFFBBF24);
  final l = name.toLowerCase();
  if (l.endsWith('.dart')) return const Color(0xFF38BDF8);
  if (l.endsWith('.py')) return const Color(0xFFFDE047);
  if (l.endsWith('.kt') || l.endsWith('.kts')) return const Color(0xFFA78BFA);
  if (l.endsWith('.java')) return const Color(0xFFFB923C);
  if (l.endsWith('.md')) return const Color(0xFF94A3B8);
  if (l.endsWith('.json') || l.endsWith('.yaml') || l.endsWith('.yml')) {
    return const Color(0xFF4ADE80);
  }
  if (l.endsWith('.apk')) return const Color(0xFF34D399);
  return const Color(0xFF94A3B8);
}

void showJarvisSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? const Color(0xFF7F1D1D) : const Color(0xFF0E2944),
        content: Text(text),
      ),
    );
}
