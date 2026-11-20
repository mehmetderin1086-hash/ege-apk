import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../services/perf_gate.dart';
import 'jarvis_ui.dart';

/// Motion switches for the Ege interface.
///
/// Looping effects run only when the user keeps "Arayüz efektleri" on, the
/// system has not asked to reduce motion, and we are not inside
/// `flutter test` (frozen there so `pumpAndSettle` can settle).
class JFx {
  JFx._();

  static final bool testing = _detectTest();

  /// Ayarlar → Görünüm → Arayüz efektleri.
  static final ValueNotifier<bool> userEnabled = ValueNotifier<bool>(true);

  static bool _detectTest() {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  static bool systemReduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// True when animated effects may run in [context].
  static bool on(BuildContext context) =>
      !testing && userEnabled.value && !systemReduced(context);

  static void haptic() {
    if (!testing) unawaited(HapticFeedback.lightImpact());
  }

  static void selection() {
    if (!testing) unawaited(HapticFeedback.selectionClick());
  }
}

/// Seconds counter driven by a [Ticker] and throttled to [fps], so painters can
/// animate continuously without rebuilding widgets every frame.
class FxClock {
  FxClock(TickerProvider vsync, {this.fps = 30}) {
    _ticker = vsync.createTicker(_tick);
  }

  final int fps;
  late final Ticker _ticker;
  final ValueNotifier<double> seconds = ValueNotifier<double>(0);
  double _offset = 0;
  Duration _lastEmit = Duration.zero;

  bool get running => _ticker.isActive;

  void _tick(Duration elapsed) {
    final gap = Duration(microseconds: 1000000 ~/ fps);
    if (elapsed != Duration.zero && elapsed - _lastEmit < gap) return;
    _lastEmit = elapsed;
    seconds.value = _offset + elapsed.inMicroseconds / 1e6;
  }

  void run(bool on) {
    if (on == _ticker.isActive) return;
    if (on) {
      _lastEmit = Duration.zero;
      _ticker.start();
    } else {
      _offset = seconds.value;
      _ticker.stop();
    }
  }

  void dispose() {
    _ticker.dispose();
    seconds.dispose();
  }
}

/// Runs an [FxClock] while the widget wants it and motion is allowed.
mixin FxClockState<T extends StatefulWidget> on State<T>, TickerProvider {
  FxClock? _clock;
  bool _reduced = false;

  FxClock get fxClock => _clock ??= FxClock(this, fps: fxFps);

  /// Frames per second for this widget's clock.
  int get fxFps => 30;

  /// Override to pause the clock (e.g. while idle).
  bool get fxActive => true;

  void syncFx() {
    if (!mounted) return;
    fxClock.run(fxActive && !JFx.testing && JFx.userEnabled.value && !_reduced && !PerfGate.heavyWork.value);
  }

  void _onUserToggle() => syncFx();

  @override
  void initState() {
    super.initState();
    JFx.userEnabled.addListener(_onUserToggle);
    PerfGate.heavyWork.addListener(_onUserToggle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = JFx.systemReduced(context);
    syncFx();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFx();
  }

  @override
  void dispose() {
    JFx.userEnabled.removeListener(_onUserToggle);
    PerfGate.heavyWork.removeListener(_onUserToggle);
    _clock?.dispose();
    super.dispose();
  }
}

// ============================================================== BACKDROP

/// App-wide animated background: artwork + drifting light motes + a slow
/// scan line. Sits behind every route (MaterialApp.builder).
class HudBackdrop extends StatefulWidget {
  const HudBackdrop({
    super.key,
    required this.child,
    this.image = 'assets/ui/chat_bg.webp',
    this.particles = 34,
  });

  final Widget child;
  final String? image;
  final int particles;

  @override
  State<HudBackdrop> createState() => _HudBackdropState();
}

class _HudBackdropState extends State<HudBackdrop>
    with SingleTickerProviderStateMixin, FxClockState<HudBackdrop> {
  late final List<_Mote> _motes = _Mote.generate(widget.particles);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
         ColoredBox(color: JColors.bg),
        if (widget.image != null)
          Image.asset(
            widget.image!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        RepaintBoundary(
          child: CustomPaint(
            painter: _MotesPainter(motes: _motes, clock: fxClock.seconds),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _Mote {
  const _Mote(this.x, this.y, this.speed, this.radius, this.phase, this.twinkle, this.violet);

  final double x, y, speed, radius, phase, twinkle;
  final bool violet;

  static List<_Mote> generate(int n) {
    final r = math.Random(42);
    return List.generate(
      n,
      (_) => _Mote(
        r.nextDouble(),
        r.nextDouble(),
        0.006 + r.nextDouble() * 0.014,
        0.7 + r.nextDouble() * 1.3,
        r.nextDouble() * math.pi * 2,
        0.5 + r.nextDouble() * 1.4,
        r.nextDouble() < 0.22,
      ),
    );
  }
}

class _MotesPainter extends CustomPainter {
  _MotesPainter({required this.motes, required this.clock}) : super(repaint: clock);

  final List<_Mote> motes;
  final ValueListenable<double> clock;
  final Paint _dot = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    for (final m in motes) {
      final y = ((m.y - t * m.speed) % 1.0 + 1.0) % 1.0;
      final x = m.x + math.sin(t * 0.15 + m.phase) * 0.012;
      final s = math.sin(t * m.twinkle + m.phase);
      final a = 0.16 + 0.44 * s * s;
      final base = m.violet ? JColors.violet : JColors.accent;
      final p = Offset(x * size.width, y * size.height);
      _dot.color = base.withValues(alpha: a * 0.16);
      canvas.drawCircle(p, m.radius * 3.2, _dot);
      _dot.color = base.withValues(alpha: a);
      canvas.drawCircle(p, m.radius, _dot);
    }
    // Slow holographic scan line.
    final y = ((t / 12.0) % 1.0) * size.height * 1.3 - size.height * 0.15;
    final rect = Rect.fromLTWH(0, y - 46, size.width, 92);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            JColors.primary.withValues(alpha: 0.05),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _MotesPainter oldDelegate) => oldDelegate.motes != motes;
}

// ============================================================== BUTTONS

enum NeonTone { primary, danger, ghost }

/// Glowing call-to-action button: press squeeze, light sweep, haptics.
class NeonButton extends StatefulWidget {
  const NeonButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = NeonTone.primary,
    this.dense = false,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final NeonTone tone;
  final bool dense;
  final bool expand;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool _down = false;

  void _setDown(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final (List<Color> grad, Color fg, Color glow, Color border) = switch (widget.tone) {
      NeonTone.primary => (
          const [Color(0xFF5EEAD4), Color(0xFF22D3EE), Color(0xFF0EA5E9)],
          const Color(0xFF02131F),
          JColors.primary,
          const Color(0x00000000),
        ),
      NeonTone.danger => (
          const [Color(0xFFFB7185), Color(0xFFE11D48), Color(0xFFBE123C)],
          Colors.white,
          const Color(0xFFF43F5E),
          const Color(0x00000000),
        ),
      NeonTone.ghost => (
          [
            JColors.surfaceHi.withValues(alpha: 0.82),
            JColors.surface.withValues(alpha: 0.82),
          ],
          JColors.accent,
          JColors.primary,
          JColors.primary.withValues(alpha: 0.42),
        ),
    };
    final radius = BorderRadius.circular(widget.dense ? 12 : 15);
    final ghost = widget.tone == NeonTone.ghost;
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: widget.dense
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: grad,
        ),
        border: Border.all(color: border, width: 1.2),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: glow.withValues(alpha: ghost ? (_down ? 0.30 : 0.12) : (_down ? 0.60 : 0.34)),
                  blurRadius: _down ? 26 : 18,
                  spreadRadius: _down ? 1.5 : 0,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: widget.dense ? 17 : 19, color: fg),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: widget.dense ? 13 : 14.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setDown(true) : null,
        onTapUp: enabled ? (_) => _setDown(false) : null,
        onTapCancel: enabled ? () => _setDown(false) : null,
        onTap: enabled
            ? () {
                JFx.haptic();
                if (JFx.on(context)) _shine.forward(from: 0);
                widget.onPressed!();
              }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.45,
          child: AnimatedScale(
            scale: _down ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Stack(
              children: [
                body,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: radius,
                      child: AnimatedBuilder(
                        animation: _shine,
                        builder: (context, _) => _shine.isAnimating
                            ? CustomPaint(painter: _ShinePainter(_shine.value))
                            : const SizedBox.shrink(),
                      ),
                    ),
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

class _ShinePainter extends CustomPainter {
  _ShinePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final x = (-0.6 + t * 2.2) * size.width;
    final band = Rect.fromLTWH(x - size.width * 0.3, -size.height, size.width * 0.6, size.height * 3);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.skew(-0.45, 0);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShinePainter oldDelegate) => oldDelegate.t != t;
}

/// Circular glowing icon button (send / stop / record).
class NeonIconButton extends StatelessWidget {
  const NeonIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tone = NeonTone.primary,
    this.tooltip,
    this.size = 46,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final NeonTone tone;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final danger = tone == NeonTone.danger;
    final colors = danger
        ? const [Color(0xFFFB7185), Color(0xFFBE123C)]
        : const [Color(0xFF67E8F9), Color(0xFF0891B2)];
    final glow = danger ? const Color(0xFFF43F5E) : JColors.primary;
    final button = PressScale(
      scale: 0.9,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.45), blurRadius: 16)],
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed == null
                ? null
                : () {
                    JFx.haptic();
                    onPressed!();
                  },
            child: Icon(icon, size: size * 0.46, color: danger ? Colors.white : const Color(0xFF02131F)),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Squeezes its child while pressed; taps still reach the child.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.97, this.enabled = true});

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ============================================================== ENTRANCES

/// Fades and lifts its child into place once.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.dy = 16,
    this.enabled = true,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double dy;
  final bool enabled;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || !JFx.on(context)) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - _curve.value) * widget.dy),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

// ============================================================== SMALL FX

/// "Ege is thinking" bouncing dots.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color = const Color(0xFF1976D2), this.size = 7});

  final Color color;
  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin, FxClockState<TypingDots> {
  @override
  int get fxFps => 45;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: fxClock.seconds,
      builder: (context, t, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Builder(builder: (context) {
              final k = math.max(0.0, math.sin(t * 6 - i * 0.9));
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Transform.translate(
                  offset: Offset(0, -4 * k),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(alpha: 0.45 + 0.55 * k),
                      boxShadow: [
                        BoxShadow(color: widget.color.withValues(alpha: 0.5 * k), blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Pulsing glow dot for live/online status.
class BreathingDot extends StatefulWidget {
  const BreathingDot({super.key, required this.color, this.size = 9, this.active = true});

  final Color color;
  final double size;
  final bool active;

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin, FxClockState<BreathingDot> {
  @override
  bool get fxActive => widget.active;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: fxClock.seconds,
      builder: (context, t, _) {
        final k = widget.active ? 0.5 + 0.5 * math.sin(t * 2.6) : 0.4;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35 + 0.45 * k),
                blurRadius: 4 + 8 * k,
                spreadRadius: 0.5 + 1.5 * k,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Text with a light sweep moving across it.
class ShimmerText extends StatefulWidget {
  const ShimmerText(
    this.text, {
    super.key,
    required this.style,
    this.base = const Color(0xFF1976D2),
    this.highlight = Colors.white,
    this.period = 4.5,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final Color base;
  final Color highlight;
  final double period;
  final TextAlign? textAlign;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin, FxClockState<ShimmerText> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: fxClock.seconds,
      builder: (context, t, child) {
        // Sweep from left (-1.2) to right (+1.2), then rest for a moment.
        final phase = (t % widget.period) / widget.period;
        final dx = -1.2 + phase * 3.2;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: [widget.base, widget.base, widget.highlight, widget.base, widget.base],
            stops: const [0.0, 0.38, 0.5, 0.62, 1.0],
            transform: _SlideGradient(dx),
          ).createShader(bounds),
          child: child,
        );
      },
      child: Text(widget.text, style: widget.style, textAlign: widget.textAlign),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);

  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * dx, 0, 0);
}

/// Expanding rings around a child (microphone while recording); [level] is
/// the live input level 0..1.
class PulseRings extends StatefulWidget {
  const PulseRings({
    super.key,
    required this.active,
    required this.child,
    this.level = 0,
    this.color = const Color(0xFFF43F5E),
    this.size = 48,
  });

  final bool active;
  final Widget child;
  final double level;
  final Color color;
  final double size;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin, FxClockState<PulseRings> {
  @override
  bool get fxActive => widget.active;

  @override
  int get fxFps => 45;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (widget.active)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RingsPainter(
                    clock: fxClock.seconds,
                    level: widget.level.clamp(0.0, 1.0),
                    color: widget.color,
                  ),
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.clock, required this.level, required this.color})
      : super(repaint: clock);

  final ValueListenable<double> clock;
  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide * 0.42;
    final t = clock.value;
    final paint = Paint()..style = PaintingStyle.stroke;
    canvas.drawCircle(
      c,
      base * (1 + level * 0.35),
      Paint()..color = color.withValues(alpha: 0.16 + level * 0.25),
    );
    for (var i = 0; i < 3; i++) {
      final p = ((t * 0.85) + i / 3) % 1.0;
      paint
        ..strokeWidth = 2.2 * (1 - p) + 0.6
        ..color = color.withValues(alpha: (1 - p) * (0.45 + level * 0.4));
      canvas.drawCircle(c, base * (1 + p * (0.55 + level * 0.9)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.color != color;
}

/// Equaliser-style voice bars driven by [energy] (0..1).
class VoiceBars extends StatefulWidget {
  const VoiceBars({
    super.key,
    required this.energy,
    required this.active,
    this.color = const Color(0xFF1976D2),
    this.bars = 28,
    this.height = 34,
  });

  final double energy;
  final bool active;
  final Color color;
  final int bars;
  final double height;

  @override
  State<VoiceBars> createState() => _VoiceBarsState();
}

class _VoiceBarsState extends State<VoiceBars>
    with SingleTickerProviderStateMixin, FxClockState<VoiceBars> {
  @override
  bool get fxActive => widget.active;

  @override
  int get fxFps => 45;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BarsPainter(
            clock: fxClock.seconds,
            energy: widget.active ? widget.energy.clamp(0.0, 1.0) : 0.0,
            color: widget.color,
            bars: widget.bars,
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.clock, required this.energy, required this.color, required this.bars})
      : super(repaint: clock);

  final ValueListenable<double> clock;
  final double energy;
  final Color color;
  final int bars;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final gap = size.width / bars;
    final w = math.max(2.0, gap * 0.42);
    final mid = size.height / 2;
    final paint = Paint();
    for (var i = 0; i < bars; i++) {
      final env = math.sin(math.pi * (i + 0.5) / bars);
      final wave = (math.sin(t * 7 + i * 0.55) * 0.5 + 0.5) * 0.7 +
          (math.sin(t * 3.1 + i * 1.3) * 0.5 + 0.5) * 0.3;
      final h = size.height * (0.07 + env * (0.05 + energy * 0.88 * wave));
      final x = gap * (i + 0.5);
      paint.color = color.withValues(alpha: 0.35 + 0.6 * (h / size.height));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, mid), width: w, height: h),
          Radius.circular(w / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) =>
      oldDelegate.energy != energy || oldDelegate.color != color || oldDelegate.bars != bars;
}

/// Thin glowing horizontal line (app bar bottom edge, section dividers).
class GlowLine extends StatelessWidget {
  const GlowLine({super.key, this.color = const Color(0xFF1976D2), this.opacity = 0.55});

  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// Frosted glass surface (used sparingly: blur is costly on phone GPUs).
class FrostedPanel extends StatelessWidget {
  const FrostedPanel({
    super.key,
    required this.child,
    this.sigma = 16,
    this.colors,
    this.border,
  });

  final Widget child;
  final double sigma;
  final List<Color>? colors;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors ??
                  [
                    const Color(0xFF0A1424).withValues(alpha: 0.78),
                    const Color(0xFF050A14).withValues(alpha: 0.92),
                  ],
            ),
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The Ege emblem artwork with a slowly turning ring and breathing glow.
class JarvisEmblem extends StatefulWidget {
  const JarvisEmblem({super.key, this.size = 140, this.animated = true});

  final double size;
  final bool animated;

  @override
  State<JarvisEmblem> createState() => _JarvisEmblemState();
}

class _JarvisEmblemState extends State<JarvisEmblem>
    with SingleTickerProviderStateMixin, FxClockState<JarvisEmblem> {
  @override
  bool get fxActive => widget.animated;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: ValueListenableBuilder<double>(
        valueListenable: fxClock.seconds,
        builder: (context, t, child) {
          final k = 0.5 + 0.5 * math.sin(t * 1.8);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: s * 0.62,
                height: s * 0.62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: JColors.primary.withValues(alpha: 0.22 + 0.18 * k),
                      blurRadius: s * (0.22 + 0.1 * k),
                      spreadRadius: s * 0.02,
                    ),
                  ],
                ),
              ),
              Transform.rotate(angle: t * 0.25, child: child),
              CustomPaint(size: Size(s, s), painter: _EmblemArcs(t)),
            ],
          );
        },
        child: Image.asset(
          'assets/ui/emblem.webp',
          width: s * 0.86,
          height: s * 0.86,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stack) => Icon(
            Icons.blur_circular_rounded,
            size: s * 0.6,
            color: JColors.primary,
          ),
        ),
      ),
    );
  }
}

class _EmblemArcs extends CustomPainter {
  _EmblemArcs(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    for (var i = 0; i < 3; i++) {
      p.color = (i == 1 ? JColors.violet : JColors.primary).withValues(alpha: 0.55);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -t * 0.6 + i * math.pi * 2 / 3,
        math.pi * 0.28,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EmblemArcs oldDelegate) => oldDelegate.t != t;
}
