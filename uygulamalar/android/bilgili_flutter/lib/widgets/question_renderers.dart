import 'dart:math';
import 'package:flutter/material.dart';
import '../models/quiz_models.dart';

class QuestionVisualViewer extends StatelessWidget {
  final QuestionVisual visual;
  final Color accent;
  final VoidCallback? onZoomStart;
  final VoidCallback? onZoomEnd;

  const QuestionVisualViewer({
    super.key,
    required this.visual,
    required this.accent,
    this.onZoomStart,
    this.onZoomEnd,
  });

  void _openFullZoom(BuildContext context) async {
    onZoomStart?.call();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF060B16),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.zoom_in_rounded, color: accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        visual.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Kapat'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 3.5,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _buildVisualBody(expanded: true),
                    ),
                  ),
                ),
              ),
              if (visual.summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    visual.summary,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    onZoomEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_iconForKind(visual.kind), size: 16, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  visual.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _openFullZoom(context),
                borderRadius: BorderRadius.circular(99),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full_rounded, size: 13, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        'Büyüt',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _openFullZoom(context),
            child: _buildVisualBody(expanded: false),
          ),
        ],
      ),
    );
  }

  IconData _iconForKind(VisualKind k) {
    switch (k) {
      case VisualKind.table:
        return Icons.table_chart_rounded;
      case VisualKind.barChart:
        return Icons.bar_chart_rounded;
      case VisualKind.lineChart:
        return Icons.show_chart_rounded;
      case VisualKind.diagram:
        return Icons.interests_rounded;
      case VisualKind.image:
        return Icons.photo_rounded;
    }
  }

  Widget _buildVisualBody({required bool expanded}) {
    switch (visual.kind) {
      case VisualKind.image:
        final path = visual.assetPath;
        if (path == null) {
          return Text(visual.summary, style: const TextStyle(color: Colors.white70));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            path,
            height: expanded ? 340 : 175,
            width: double.infinity,
            fit: BoxFit.contain,
          ),
        );

      case VisualKind.table:
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Table(
            border: TableBorder.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1,
            ),
            children: [
              if (visual.columns.isNotEmpty)
                TableRow(
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.18)),
                  children: [
                    for (final col in visual.columns)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: Text(
                          col,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              for (final row in visual.rows)
                TableRow(
                  children: [
                    for (var i = 0; i < visual.columns.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Text(
                          i < row.length ? row[i] : '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );

      case VisualKind.barChart:
      case VisualKind.lineChart:
        final series = List.generate(visual.values.length, (i) {
          final label = i < visual.labels.length ? visual.labels[i] : '${i + 1}';
          return '$label: ${_chartNumber(visual.values[i])} ${visual.unit ?? ''}'.trim();
        });
        final chart = SizedBox(
          height: expanded ? 230 : 155,
          child: CustomPaint(
            size: Size.infinite,
            painter: visual.kind == VisualKind.barChart
                ? _BarChartPainter(labels: visual.labels, values: visual.values,
                    unit: visual.unit, accent: accent)
                : _LineChartPainter(labels: visual.labels, values: visual.values,
                    unit: visual.unit, accent: accent),
          ),
        );
        return Semantics(
          label: series.join('. '),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            chart,
            if (expanded) Wrap(
              alignment: WrapAlignment.center, spacing: 14, runSpacing: 4,
              children: [for (final entry in series)
                Text(entry, style: const TextStyle(color: Colors.white, fontSize: 12))],
            ),
          ]),
        );

      case VisualKind.diagram:
        return SizedBox(
          height: expanded ? 260 : 165,
          child: CustomPaint(
            size: Size.infinite,
            painter: _DiagramPainter(elements: visual.elements, defaultAccent: accent),
          ),
        );
    }
  }
}

String _chartNumber(double value) {
  if (value == value.truncateToDouble()) return '${value.toInt()}';
  final text = value != 0 && value.abs() < 1e-6
      ? value.toStringAsExponential(3)
      : value.toStringAsFixed(8).replaceFirst(RegExp(r'0+$'), '');
  return text.replaceAll('.', ',');
}

class _BarChartPainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  final String? unit;
  final Color accent;

  _BarChartPainter({
    required this.labels,
    required this.values,
    this.unit,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = max(values.reduce(max), 0.0);
    final minVal = min(values.reduce(min), 0.0);
    final span = maxVal == minVal ? 1.0 : maxVal - minVal;
    final bottom = size.height - 26;
    final top = 22.0;
    final chartH = max(bottom - top, 20.0);

    final zero = bottom + minVal / span * chartH;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(8, zero), Offset(size.width - 8, zero), gridPaint);

    final slotW = (size.width - 20) / values.length;
    final barW = min(slotW * 0.54, 42.0);

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final y = bottom - (v - minVal) / span * chartH;
      final h = (zero - y).abs();
      final cx = 10 + slotW * (i + 0.5);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, min(zero, y), barW, max(0.01, h)),
        topLeft: const Radius.circular(7),
        topRight: const Radius.circular(7),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [accent, accent.withValues(alpha: 0.45)],
          ).createShader(rect.outerRect),
      );

      final valStr = _chartNumber(v);
      final valTp = TextPainter(
        text: TextSpan(
          text: unit != null && i == values.length - 1 ? '$valStr $unit' : valStr,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slotW + 14);
      valTp.paint(canvas, Offset(cx - valTp.width / 2, (y - 16).clamp(0, bottom - 14).toDouble()));

      if (i < labels.length) {
        final lblTp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.78)),
          ),
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: slotW - 2);
        lblTp.paint(canvas, Offset(cx - lblTp.width / 2, bottom + 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      values != oldDelegate.values || labels != oldDelegate.labels ||
      unit != oldDelegate.unit || accent != oldDelegate.accent;
}

class _LineChartPainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  final String? unit;
  final Color accent;

  _LineChartPainter({
    required this.labels,
    required this.values,
    this.unit,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = max(values.reduce(max), 1.0);
    final minVal = min(0.0, values.reduce(min));
    final span = max(maxVal - minVal, 1.0);
    final bottom = size.height - 26;
    final top = 24.0;
    final chartH = max(bottom - top, 20.0);

    final pts = <Offset>[];
    final count = values.length;
    final zeroY = bottom + minVal / span * chartH;
    for (var i = 0; i < count; i++) {
      final x = count == 1
          ? size.width / 2
          : 24 + (size.width - 48) * (i / (count - 1));
      final y = bottom - ((values[i] - minVal) / span) * chartH;
      pts.add(Offset(x, y));
    }

    canvas.drawLine(
      Offset(14, zeroY),
      Offset(size.width - 14, zeroY),
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );

    if (pts.length >= 2) {
      final fillPath = Path()..moveTo(pts.first.dx, zeroY);
      for (final p in pts) {
        fillPath.lineTo(p.dx, p.dy);
      }
      fillPath.lineTo(pts.last.dx, zeroY);
      fillPath.close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [accent.withValues(alpha: 0.30), accent.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, top, size.width, chartH)),
      );

      final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        linePath.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(
        linePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = accent,
      );
    }

    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      canvas.drawCircle(p, 4.5, Paint()..color = accent);
      canvas.drawCircle(p, 2.0, Paint()..color = Colors.white);

      final v = values[i];
      final valStr = _chartNumber(v);
      final valTp = TextPainter(
        text: TextSpan(
          text: valStr,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(canvas, Offset(p.dx - valTp.width / 2, p.dy - 17));

      if (i < labels.length) {
        final lblTp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.78)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        lblTp.paint(canvas, Offset(p.dx - lblTp.width / 2, bottom + 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      values != oldDelegate.values || labels != oldDelegate.labels ||
      unit != oldDelegate.unit || accent != oldDelegate.accent;
}

class _DiagramPainter extends CustomPainter {
  final List<DiagramElement> elements;
  final Color defaultAccent;

  _DiagramPainter({required this.elements, required this.defaultAccent});

  Color _resolveColor(String? name) {
    switch (name?.toLowerCase()) {
      case 'mint':
        return const Color(0xFF4CE0D2);
      case 'blue':
        return const Color(0xFF5AB2FF);
      case 'gold':
        return const Color(0xFFF6C453);
      case 'pink':
        return const Color(0xFFFF7BAC);
      case 'violet':
        return const Color(0xFFB88CFF);
      default:
        return defaultAccent;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final el in elements) {
      final color = _resolveColor(el.color);
      final cx = (el.x / 100.0) * size.width;
      final cy = (el.y / 100.0) * size.height;
      final w = ((el.width ?? 16) / 100.0) * size.width;
      final h = ((el.height ?? 16) / 100.0) * size.height;

      final fill = Paint()..color = color.withValues(alpha: 0.24);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = color;

      switch (el.shape) {
        case 'rectangle':
          final r = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
            const Radius.circular(6),
          );
          canvas.drawRRect(r, fill);
          canvas.drawRRect(r, stroke);
          break;
        case 'circle':
          final radius = min(w, h) / 2;
          canvas.drawCircle(Offset(cx, cy), max(radius, 6), fill);
          canvas.drawCircle(Offset(cx, cy), max(radius, 6), stroke);
          break;
        case 'triangle':
          final path = Path()
            ..moveTo(cx, cy - h / 2)
            ..lineTo(cx + w / 2, cy + h / 2)
            ..lineTo(cx - w / 2, cy + h / 2)
            ..close();
          canvas.drawPath(path, fill);
          canvas.drawPath(path, stroke);
          break;
        case 'point':
          canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = color);
          break;
        case 'line':
        case 'arrow':
          final ex = ((el.endX ?? el.x) / 100.0) * size.width;
          final ey = ((el.endY ?? el.y) / 100.0) * size.height;
          canvas.drawLine(Offset(cx, cy), Offset(ex, ey), stroke);
          if (el.shape == 'arrow') {
            final angle = atan2(ey - cy, ex - cx);
            const head = 8.0;
            final p1 = Offset(ex - head * cos(angle - 0.45), ey - head * sin(angle - 0.45));
            final p2 = Offset(ex - head * cos(angle + 0.45), ey - head * sin(angle + 0.45));
            canvas.drawLine(Offset(ex, ey), p1, stroke);
            canvas.drawLine(Offset(ex, ey), p2, stroke);
          }
          break;
        case 'text':
          break;
      }

      if (el.label != null && el.label!.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: el.label!,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width * 0.45);
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DiagramPainter oldDelegate) =>
      elements != oldDelegate.elements || defaultAccent != oldDelegate.defaultAccent;
}

class QuestionActivityWidget extends StatefulWidget {
  final Question question;
  final Color accent;
  final bool revealed;
  final VoidCallback onPlayListeningAudio;
  final VoidCallback onStartPronunciationMic;
  final void Function(List<int> sequence) onSubmitSequence;
  final void Function(int optionIndex) onSelectChoice;

  const QuestionActivityWidget({
    super.key,
    required this.question,
    required this.accent,
    required this.revealed,
    required this.onPlayListeningAudio,
    required this.onStartPronunciationMic,
    required this.onSubmitSequence,
    required this.onSelectChoice,
  });

  @override
  State<QuestionActivityWidget> createState() => _QuestionActivityWidgetState();
}

class _QuestionActivityWidgetState extends State<QuestionActivityWidget> {
  final List<int> _orderedPick = [];
  int? _activeLeftIndex;
  final Map<int, int> _leftToRight = {};
  bool _showTranscript = false;

  @override
  void didUpdateWidget(covariant QuestionActivityWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _orderedPick.clear();
      _activeLeftIndex = null;
      _leftToRight.clear();
      _showTranscript = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final act = widget.question.activity;
    if (act == null) return const SizedBox.shrink();

    switch (act.kind) {
      case ActivityKind.listening:
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.headphones_rounded, color: widget.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      act.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: widget.accent,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onPlayListeningAudio,
                    icon: const Icon(Icons.volume_up_rounded, size: 17),
                    label: const Text('Metni Dinle'),
                  ),
                ],
              ),
              if (_showTranscript && act.transcript != null) ...[
                const SizedBox(height: 6),
                Text(
                  act.transcript!,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ] else if (act.transcript != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () => setState(() => _showTranscript = true),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Sessiz ortamdaysan yazılı metni göster',
                        style: TextStyle(
                          fontSize: 11.5,
                          decoration: TextDecoration.underline,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

      case ActivityKind.ordering:
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.accent.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.swap_vert_rounded, size: 17, color: widget.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${act.title} · Sırayla dokun',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: widget.accent,
                      ),
                    ),
                  ),
                  if (_orderedPick.isNotEmpty && !widget.revealed)
                    InkWell(
                      onTap: () => setState(_orderedPick.clear),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          'Sıfırla',
                          style: TextStyle(fontSize: 11.5, color: Colors.white70),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < act.items.length; i++)
                    _buildOrderChip(i, act.items[i]),
                ],
              ),
              if (!widget.revealed) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _orderedPick.length == act.items.length
                      ? () => widget.onSubmitSequence(List<int>.from(_orderedPick))
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: const Color(0xFF06101F),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    _orderedPick.length == act.items.length
                        ? 'Sıralamayı Onayla'
                        : '${_orderedPick.length}/${act.items.length} öğe seçildi',
                  ),
                ),
              ],
            ],
          ),
        );

      case ActivityKind.matching:
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.accent.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.compare_arrows_rounded, size: 17, color: widget.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${act.title} · Önce sol, sonra sağ kutuya dokun',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: widget.accent,
                      ),
                    ),
                  ),
                  if (_leftToRight.isNotEmpty && !widget.revealed)
                    InkWell(
                      onTap: () => setState(() {
                        _leftToRight.clear();
                        _activeLeftIndex = null;
                      }),
                      child: const Text(
                        'Temizle',
                        style: TextStyle(fontSize: 11.5, color: Colors.white70),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        for (var i = 0; i < act.left.length; i++)
                          _buildMatchLeftTile(i, act.left[i]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      children: [
                        for (var j = 0; j < act.right.length; j++)
                          _buildMatchRightTile(j, act.right[j]),
                      ],
                    ),
                  ),
                ],
              ),
              if (!widget.revealed) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _leftToRight.length == act.left.length
                      ? () {
                          final seq = [
                            for (var i = 0; i < act.left.length; i++) _leftToRight[i] ?? 0
                          ];
                          widget.onSubmitSequence(seq);
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: const Color(0xFF06101F),
                  ),
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: Text(
                    _leftToRight.length == act.left.length
                        ? 'Eşleştirmeyi Onayla'
                        : '${_leftToRight.length}/${act.left.length} eşleşti',
                  ),
                ),
              ],
            ],
          ),
        );

      case ActivityKind.pronunciation:
        final phrase = act.transcript ?? widget.question.options.first;
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.accent.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.record_voice_over_rounded, color: widget.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${act.title} (${act.language ?? "en-US"})',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: widget.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '"$phrase"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onPlayListeningAudio,
                      icon: const Icon(Icons.volume_up_rounded, size: 17),
                      label: const Text('Örneği Dinle'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.revealed ? null : widget.onStartPronunciationMic,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.accent,
                        foregroundColor: const Color(0xFF06101F),
                      ),
                      icon: const Icon(Icons.mic_rounded, size: 18),
                      label: const Text('Sözcükleri söyle'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Mikrofon, tanınan sözcüklerin örnekle aynı sırada olmasını kontrol eder.',
                style: TextStyle(fontSize: 11.5, color: Colors.white70)),
            ],
          ),
        );
    }
  }

  Widget _buildOrderChip(int index, String label) {
    final pos = _orderedPick.indexOf(index);
    final selected = pos >= 0;
    return InkWell(
      onTap: widget.revealed
          ? null
          : () {
              setState(() {
                if (selected) {
                  _orderedPick.remove(index);
                } else {
                  _orderedPick.add(index);
                }
              });
            },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? widget.accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.07),
          border: Border.all(
            color: selected ? widget.accent : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              CircleAvatar(
                radius: 10,
                backgroundColor: widget.accent,
                child: Text(
                  '${pos + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF06101F),
                  ),
                ),
              ),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _pairColors = [
    Color(0xFF4CE0D2),
    Color(0xFFF6C453),
    Color(0xFF5AB2FF),
    Color(0xFFFF7BAC),
  ];

  Widget _buildMatchLeftTile(int i, String text) {
    final isActive = _activeLeftIndex == i;
    final matchedRight = _leftToRight[i];
    final c = _pairColors[i % _pairColors.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: widget.revealed
            ? null
            : () => setState(() => _activeLeftIndex = isActive ? null : i),
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: isActive || matchedRight != null
                ? c.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: isActive || matchedRight != null
                  ? c
                  : Colors.white.withValues(alpha: 0.15),
              width: isActive ? 1.6 : 1.0,
            ),
          ),
          child: Text(
            '${i + 1}. $text',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatchRightTile(int j, String text) {
    int? ownerLeft;
    for (final e in _leftToRight.entries) {
      if (e.value == j) {
        ownerLeft = e.key;
        break;
      }
    }
    final c = ownerLeft != null ? _pairColors[ownerLeft % _pairColors.length] : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: widget.revealed
            ? null
            : () {
                final left = _activeLeftIndex;
                if (left == null) return;
                setState(() {
                  _leftToRight.removeWhere((_, v) => v == j);
                  _leftToRight[left] = j;
                  _activeLeftIndex = null;
                });
              },
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: c != null
                ? c.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: c ?? Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              if (ownerLeft != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${ownerLeft + 1}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF06101F),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
