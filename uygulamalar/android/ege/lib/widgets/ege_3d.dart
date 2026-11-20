import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'jarvis_fx.dart';

/// Canlı Ses için gerçek perspektifli 3D küre.
///
/// İçte ışıklandırılmış bir çekirdek; dışta Fibonacci dağılımlı nokta
/// bulutu iki eksende döner, derinliğe göre boyut ve saydamlık alır. Konuşma
/// enerjisi [energy] noktaları dışa iter ve dalgalandırır. Hareket kapalıysa
/// (sistem ayarı, kullanıcı ayarı, test) tek kare çizilir.
class Ege3DOrb extends StatefulWidget {
  const Ege3DOrb({
    super.key,
    required this.size,
    required this.color,
    this.energy = 0,
    this.active = false,
  });

  final double size;
  final Color color;
  final double energy;
  final bool active;

  @override
  State<Ege3DOrb> createState() => _Ege3DOrbState();
}

class _Ege3DOrbState extends State<Ege3DOrb>
    with SingleTickerProviderStateMixin, FxClockState<Ege3DOrb> {
  // Enerji ani sıçramasın: her karede hedefe yumuşakça yaklaşır.
  double _smooth = 0;

  @override
  int get fxFps => 45;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: ValueListenableBuilder<double>(
          valueListenable: fxClock.seconds,
          builder: (context, t, _) {
            _smooth += (widget.energy.clamp(0.0, 1.0) - _smooth) * 0.18;
            return CustomPaint(
              key: const Key('ege_3d_orb'),
              painter: _OrbPainter(
                t: t,
                color: widget.color,
                energy: _smooth,
                active: widget.active,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.t,
    required this.color,
    required this.energy,
    required this.active,
  });

  final double t;
  final Color color;
  final double energy;
  final bool active;

  static const int _count = 420;
  static final List<List<double>> _points = _fibonacciSphere(_count);

  static List<List<double>> _fibonacciSphere(int n) {
    final golden = math.pi * (3 - math.sqrt(5));
    return List.generate(n, (i) {
      final y = 1 - (i / (n - 1)) * 2;
      final r = math.sqrt(1 - y * y);
      final th = golden * i;
      return [math.cos(th) * r, y, math.sin(th) * r];
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.shortestSide * 0.36;
    final speed = active ? 0.55 : 0.22;
    final ay = t * speed;
    final ax = 0.42 + math.sin(t * 0.31) * 0.18;
    final cosY = math.cos(ay), sinY = math.sin(ay);
    final cosX = math.cos(ax), sinX = math.sin(ax);
    const camera = 3.2;

    // Yumuşak dış ışıma.
    canvas.drawCircle(
      c,
      radius * (1.55 + energy * 0.25),
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.20 + energy * 0.18),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: radius * 1.8)),
    );

    // Noktaları döndür, yansıt, derinliğe göre sırala.
    final projected = <(double z, Offset p, double s)>[];
    for (var i = 0; i < _points.length; i++) {
      final p = _points[i];
      // Enerjiye bağlı dalga: yüzey nefes alır.
      final wave =
          1 +
          energy * 0.22 * math.sin(t * 6 + p[1] * 5 + p[0] * 3) +
          (active ? 0.02 * math.sin(t * 2 + i) : 0);
      var x = p[0] * wave, y = p[1] * wave, z = p[2] * wave;
      // Y ekseni
      final x1 = x * cosY + z * sinY;
      final z1 = -x * sinY + z * cosY;
      // X ekseni
      final y2 = y * cosX - z1 * sinX;
      final z2 = y * sinX + z1 * cosX;
      x = x1;
      y = y2;
      z = z2;
      final persp = camera / (camera - z);
      projected.add((
        z,
        Offset(
          c.dx + x * radius * 1.30 * persp,
          c.dy + y * radius * 1.30 * persp,
        ),
        persp,
      ));
    }
    projected.sort((a, b) => a.$1.compareTo(b.$1));

    // Arka yarıküre noktaları (çekirdeğin arkasında kalır).
    final dot = Paint();
    void drawDots(bool front) {
      for (final (z, p, s) in projected) {
        if ((z >= 0) != front) continue;
        final depth = (z + 1) / 2; // 0 arka, 1 ön
        dot.color = Color.lerp(color, Colors.white, depth * 0.55)!.withValues(
          alpha: front && (p - c).distance < radius * (0.64 + energy * 0.08)
              ? 0.10 + depth * 0.35
              : 0.18 + depth * 0.72,
        );
        canvas.drawCircle(p, (0.55 + depth * 1.25) * s, dot);
      }
    }

    drawDots(false);

    // Işıklandırılmış çekirdek küre (sol üstten ışık).
    final core = radius * (0.62 + energy * 0.08);
    final coreRect = Rect.fromCircle(center: c, radius: core);
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.38, -0.45),
          radius: 1.05,
          colors: [
            Color.lerp(color, Colors.white, 0.62)!,
            Color.lerp(color, Colors.white, 0.12)!,
            color,
            Color.lerp(color, Colors.black, 0.45)!,
          ],
          stops: const [0.0, 0.35, 0.72, 1.0],
        ).createShader(coreRect),
    );
    // Parlak nokta (speküler).
    canvas.drawCircle(
      c + Offset(-core * 0.34, -core * 0.40),
      core * 0.22,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.75),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: c + Offset(-core * 0.34, -core * 0.40),
                radius: core * 0.22,
              ),
            ),
    );
    // Ekvator halkası (eğik elips): derinlik hissi.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 2.5,
        height: radius * (0.55 + 0.1 * math.sin(t * 0.8)),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = color.withValues(alpha: 0.38 + energy * 0.3),
    );
    canvas.restore();

    drawDots(true);
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t ||
      old.color != color ||
      old.energy != energy ||
      old.active != active;
}

/// Dokunulan yere doğru 3D eğilen kart sarmalayıcı (perspektif dönüş).
/// Parmak kalkınca yaya benzer bir yumuşaklıkla düzleşir.
class Tilt3D extends StatefulWidget {
  const Tilt3D({super.key, required this.child, this.maxAngle = 0.12});

  final Widget child;
  final double maxAngle;

  @override
  State<Tilt3D> createState() => _Tilt3DState();
}

class _Tilt3DState extends State<Tilt3D> with SingleTickerProviderStateMixin {
  Offset _target = Offset.zero;
  Offset _now = Offset.zero;
  late final Ticker _ticker = createTicker(_tick);

  void _tick(Duration _) {
    final next = Offset.lerp(_now, _target, 0.22)!;
    if ((next - _target).distance < 0.001) {
      _ticker.stop();
      setState(() => _now = _target);
      return;
    }
    setState(() => _now = next);
  }

  void _aim(Offset local, Size size) {
    if (!JFx.on(context) || size.isEmpty) return;
    final dx = (local.dx / size.width - 0.5) * 2;
    final dy = (local.dy / size.height - 0.5) * 2;
    _target = Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
    if (!_ticker.isActive) _ticker.start();
  }

  void _release() {
    _target = Offset.zero;
    if (!_ticker.isActive && _now != Offset.zero) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(
          box.hasBoundedWidth ? box.maxWidth : 0,
          box.hasBoundedHeight ? box.maxHeight : 0,
        );
        return Listener(
          onPointerDown: (e) => _aim(e.localPosition, context.size ?? size),
          onPointerMove: (e) => _aim(e.localPosition, context.size ?? size),
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => _release(),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0014)
              ..rotateX(-_now.dy * widget.maxAngle)
              ..rotateY(_now.dx * widget.maxAngle),
            child: widget.child,
          ),
        );
      },
    );
  }
}
