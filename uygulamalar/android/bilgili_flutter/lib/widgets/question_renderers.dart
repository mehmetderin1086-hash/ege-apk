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
        border: Border.all(color: accent.withValues(alpha: 0.30)),
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
      case VisualKind.pieChart:
        return Icons.pie_chart_rounded;
      case VisualKind.clock:
        return Icons.schedule_rounded;
      case VisualKind.flag:
        return Icons.flag_rounded;
      case VisualKind.musicStaff:
        return Icons.music_note_rounded;
      case VisualKind.coordPlane:
        return Icons.grid_on_rounded;
      case VisualKind.atom:
        return Icons.science_rounded;
      case VisualKind.matrix:
        return Icons.apps_rounded;
      case VisualKind.circuit:
        return Icons.memory_rounded;
      case VisualKind.venn:
        return Icons.donut_large_rounded;
      case VisualKind.compass:
        return Icons.explore_rounded;
      case VisualKind.colorLab:
        return Icons.palette_rounded;
      case VisualKind.piano:
        return Icons.piano_rounded;
    }
  }

  static const _pieColors = [
    Color(0xFFF6C453),
    Color(0xFF4CE0D2),
    Color(0xFF5AB2FF),
    Color(0xFFFF7BAC),
    Color(0xFFB88CFF),
    Color(0xFF7BE495),
  ];

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
                ? _BarChartPainter(
                    labels: visual.labels,
                    values: visual.values,
                    unit: visual.unit,
                    accent: accent,
                  )
                : _LineChartPainter(
                    labels: visual.labels,
                    values: visual.values,
                    unit: visual.unit,
                    accent: accent,
                  ),
          ),
        );
        return Semantics(
          label: series.join('. '),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              chart,
              if (expanded)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final entry in series)
                      Text(entry, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
            ],
          ),
        );

      case VisualKind.diagram:
        return SizedBox(
          height: expanded ? 260 : 165,
          child: CustomPaint(
            size: Size.infinite,
            painter: _DiagramPainter(elements: visual.elements, defaultAccent: accent),
          ),
        );

      case VisualKind.pieChart:
        final total = visual.values.fold<double>(0, (s, v) => s + max(0, v));
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: expanded ? 230 : 158,
              child: CustomPaint(
                size: Size.infinite,
                painter: _PieChartPainter(
                  labels: visual.labels,
                  values: visual.values,
                  unit: visual.unit,
                  colors: _pieColors,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 5,
              children: [
                for (var i = 0; i < visual.values.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: _pieColors[i % _pieColors.length].withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: _pieColors[i % _pieColors.length].withValues(alpha: 0.55),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _pieColors[i % _pieColors.length],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${i < visual.labels.length ? visual.labels[i] : '${i + 1}'}: '
                          '${_chartNumber(visual.values[i])}${visual.unit != null ? ' ${visual.unit}' : ''}'
                          '${total > 0 && visual.unit != '%' ? ' (%${((visual.values[i] / total) * 100).round()})' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );

      case VisualKind.clock:
        final hour = visual.values.isNotEmpty ? visual.values[0].toInt() : 12;
        final minute = visual.values.length > 1 ? visual.values[1].toInt() : 0;
        final showAngle = visual.values.length > 2 && visual.values[2] > 0.5;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: expanded ? 250 : 168,
              child: CustomPaint(
                size: Size.infinite,
                painter: _ClockVisualPainter(
                  hour: hour,
                  minute: minute,
                  showAngle: showAngle,
                  accent: accent,
                ),
              ),
            ),
            if (visual.unit != null && visual.unit!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Text(
                  visual.unit!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ],
        );

      case VisualKind.flag:
        final code = (visual.imageID ?? 'TR').toUpperCase();
        return Center(
          child: Container(
            width: expanded ? 320 : 216,
            height: expanded ? 213 : 144,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                size: Size.infinite,
                painter: _FlagVisualPainter(code: code),
              ),
            ),
          ),
        );

      case VisualKind.musicStaff:
        final clef = visual.unit ?? 'treble';
        final isChord = visual.columns.contains('chord');
        return SizedBox(
          height: expanded ? 220 : 146,
          child: CustomPaint(
            size: Size.infinite,
            painter: _MusicStaffPainter(
              clef: clef,
              notes: visual.labels,
              isChord: isChord,
              accent: accent,
            ),
          ),
        );

      case VisualKind.coordPlane:
        final minX = visual.values.length >= 4 ? visual.values[0] : -5.0;
        final maxX = visual.values.length >= 4 ? visual.values[1] : 5.0;
        final minY = visual.values.length >= 4 ? visual.values[2] : -5.0;
        final maxY = visual.values.length >= 4 ? visual.values[3] : 5.0;
        return SizedBox(
          height: expanded ? 280 : 186,
          child: CustomPaint(
            size: Size.infinite,
            painter: _CoordPlanePainter(
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              elements: visual.elements,
              accent: accent,
            ),
          ),
        );

      case VisualKind.atom:
        final protons = visual.values.isNotEmpty ? visual.values[0].toInt() : 6;
        final neutrons = visual.values.length > 1 ? visual.values[1].toInt() : 6;
        final shells = visual.values.length > 2
            ? visual.values.sublist(2).map((e) => e.toInt()).toList()
            : const <int>[2, 4];
        final centerLabel = visual.labels.isNotEmpty ? visual.labels.first : '?';
        const shellNames = ['K', 'L', 'M', 'N'];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: expanded ? 245 : 172,
              child: CustomPaint(
                size: Size.infinite,
                painter: _AtomVisualPainter(
                  protons: protons,
                  neutrons: neutrons,
                  shells: shells,
                  centerLabel: centerLabel,
                  accent: accent,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < shells.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CE0D2).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: const Color(0xFF4CE0D2).withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      '${i < shellNames.length ? shellNames[i] : 'S${i + 1}'}: ${shells[i]}e⁻',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (visual.unit != null && visual.unit!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: accent.withValues(alpha: 0.55)),
                    ),
                    child: Text(
                      visual.unit!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );

      case VisualKind.matrix:
        return Center(
          child: SizedBox(
            width: expanded ? 280 : 196,
            height: expanded ? 280 : 196,
            child: CustomPaint(
              size: Size.infinite,
              painter: _PatternMatrixPainter(rows: visual.rows, accent: accent),
            ),
          ),
        );

      case VisualKind.circuit:
        return SizedBox(
          height: expanded ? 245 : 168,
          child: CustomPaint(
            size: Size.infinite,
            painter: _CircuitVisualPainter(
              mode: visual.unit ?? 'logic',
              labels: visual.labels,
              values: visual.values,
              accent: accent,
            ),
          ),
        );

      case VisualKind.venn:
        return SizedBox(
          height: expanded ? 250 : 178,
          child: CustomPaint(
            size: Size.infinite,
            painter: _VennVisualPainter(
              labels: visual.labels,
              values: visual.values,
              highlight: visual.unit ?? 'none',
              accent: accent,
            ),
          ),
        );

      case VisualKind.compass:
        final deg = visual.values.isNotEmpty ? visual.values[0] : 0.0;
        final turn = visual.values.length > 1 ? visual.values[1] : 0.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: expanded ? 250 : 176,
              child: CustomPaint(
                size: Size.infinite,
                painter: _CompassVisualPainter(
                  bearingDeg: deg,
                  turnDeg: turn,
                  accent: accent,
                ),
              ),
            ),
            if (visual.unit != null && visual.unit!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Text(
                  visual.unit!,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: accent),
                ),
              ),
            ],
          ],
        );

      case VisualKind.colorLab:
        return SizedBox(
          height: expanded ? 220 : 156,
          child: CustomPaint(
            size: Size.infinite,
            painter: _ColorLabVisualPainter(
              mode: visual.unit ?? 'mix',
              labels: visual.labels,
              values: visual.values,
              accent: accent,
            ),
          ),
        );

      case VisualKind.piano:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: expanded ? 170 : 120,
              child: CustomPaint(
                size: Size.infinite,
                painter: _PianoVisualPainter(
                  highlightedKeys: visual.labels,
                  accent: accent,
                ),
              ),
            ),
            if (visual.unit != null && visual.unit!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Text(
                  visual.unit!,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent),
                ),
              ),
            ],
          ],
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
      values != oldDelegate.values ||
      labels != oldDelegate.labels ||
      unit != oldDelegate.unit ||
      accent != oldDelegate.accent;
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
      values != oldDelegate.values ||
      labels != oldDelegate.labels ||
      unit != oldDelegate.unit ||
      accent != oldDelegate.accent;
}

class _PieChartPainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  final String? unit;
  final List<Color> colors;

  _PieChartPainter({
    required this.labels,
    required this.values,
    this.unit,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final total = values.fold<double>(0, (s, v) => s + max(0.0, v));
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.44;
    final innerR = radius * 0.48;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Subtle 3D depth shadow
    canvas.drawCircle(
      center + const Offset(0, 4),
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    var start = -pi / 2;
    for (var i = 0; i < values.length; i++) {
      final v = max(0.0, values[i]);
      final sweep = (v / total) * 2 * pi;
      final c = colors[i % colors.length];
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = c,
      );
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFF0A1138),
      );
      final pct = ((v / total) * 100).round();
      if (pct >= 10) {
        final mid = start + sweep / 2;
        final labelR = (radius + innerR) * 0.52;
        final pos = Offset(center.dx + cos(mid) * labelR, center.dy + sin(mid) * labelR);
        final tp = TextPainter(
          text: TextSpan(
            text: '%$pct',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF061028),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
      }
      start += sweep;
    }

    // Donut hole
    canvas.drawCircle(center, innerR, Paint()..color = const Color(0xFF0A1240));
    canvas.drawCircle(
      center,
      innerR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFFF6C453).withValues(alpha: 0.55),
    );

    final totalStr = unit == '%' ? '%100' : _chartNumber(total);
    final totalTp = TextPainter(
      text: TextSpan(
        text: totalStr,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w900,
          color: Color(0xFFFFE082),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    totalTp.paint(
      canvas,
      Offset(center.dx - totalTp.width / 2, center.dy - totalTp.height / 2 - (unit != null && unit != '%' ? 5 : 0)),
    );
    if (unit != null && unit != '%') {
      final uTp = TextPainter(
        text: TextSpan(
          text: unit,
          style: TextStyle(fontSize: 9.5, color: Colors.white.withValues(alpha: 0.72)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      uTp.paint(canvas, Offset(center.dx - uTp.width / 2, center.dy + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter old) =>
      old.values != values || old.labels != labels || old.unit != unit;
}

class _ClockVisualPainter extends CustomPainter {
  final int hour;
  final int minute;
  final bool showAngle;
  final Color accent;

  _ClockVisualPainter({
    required this.hour,
    required this.minute,
    required this.showAngle,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) * 0.45;

    // Outer metallic gold bezel
    canvas.drawCircle(
      center,
      r + 4,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE082), Color(0xFFC48B1A), Color(0xFFF6C453)],
        ).createShader(Rect.fromCircle(center: center, radius: r + 4)),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF15256E), Color(0xFF070D2E)],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // 60 ticks & 12 numbers
    for (var i = 0; i < 60; i++) {
      final a = (i * 6 - 90) * pi / 180;
      final isMajor = i % 5 == 0;
      final p1 = Offset(center.dx + cos(a) * (r - (isMajor ? 10 : 5)),
          center.dy + sin(a) * (r - (isMajor ? 10 : 5)));
      final p2 = Offset(center.dx + cos(a) * (r - 2), center.dy + sin(a) * (r - 2));
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = isMajor ? accent : Colors.white.withValues(alpha: 0.30)
          ..strokeWidth = isMajor ? 2.0 : 1.0
          ..strokeCap = StrokeCap.round,
      );
      if (isMajor) {
        final numVal = i == 0 ? 12 : i ~/ 5;
        final nr = r - 21;
        final np = Offset(center.dx + cos(a) * nr, center.dy + sin(a) * nr);
        final tp = TextPainter(
          text: TextSpan(
            text: '$numVal',
            style: TextStyle(
              fontSize: numVal % 3 == 0 ? 12.5 : 10.5,
              fontWeight: FontWeight.w900,
              color: numVal % 3 == 0 ? const Color(0xFFFFE082) : Colors.white.withValues(alpha: 0.85),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(np.dx - tp.width / 2, np.dy - tp.height / 2));
      }
    }

    final hDeg = ((hour % 12) * 30.0 + minute * 0.5) % 360.0;
    final mDeg = (minute * 6.0) % 360.0;
    final hRad = (hDeg - 90) * pi / 180;
    final mRad = (mDeg - 90) * pi / 180;

    if (showAngle) {
      var diff = (mDeg - hDeg) % 360.0;
      if (diff < 0) diff += 360.0;
      final startRad = diff <= 180 ? hRad : mRad;
      final sweepRad = (diff <= 180 ? diff : 360.0 - diff) * pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * 0.42),
        startRad,
        sweepRad,
        true,
        Paint()..color = const Color(0xFF4CE0D2).withValues(alpha: 0.24),
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * 0.42),
        startRad,
        sweepRad,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = const Color(0xFF4CE0D2),
      );
    }

    // Hour hand (gold)
    canvas.drawLine(
      center,
      Offset(center.dx + cos(hRad) * r * 0.50, center.dy + sin(hRad) * r * 0.50),
      Paint()
        ..color = const Color(0xFFFFD86B)
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round,
    );
    // Minute hand (bright cyan-white)
    canvas.drawLine(
      center,
      Offset(center.dx + cos(mRad) * r * 0.72, center.dy + sin(mRad) * r * 0.72),
      Paint()
        ..color = const Color(0xFF7CEEFF)
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );
    // Center pin
    canvas.drawCircle(center, 5.2, Paint()..color = accent);
    canvas.drawCircle(center, 2.2, Paint()..color = const Color(0xFF0A1240));
  }

  @override
  bool shouldRepaint(covariant _ClockVisualPainter old) =>
      old.hour != hour || old.minute != minute || old.showAngle != showAngle;
}

class _FlagVisualPainter extends CustomPainter {
  final String code;
  _FlagVisualPainter({required this.code});

  static const _red = Color(0xFFD9252E);
  static const _darkRed = Color(0xFFA61728);
  static const _crimson = Color(0xFFE30A17);
  static const _white = Color(0xFFF7F9FC);
  static const _navy = Color(0xFF0B256B);
  static const _blue = Color(0xFF0055A4);
  static const _sky = Color(0xFF4FA8E8);
  static const _gold = Color(0xFFF7C91E);
  static const _green = Color(0xFF007A3D);
  static const _darkGreen = Color(0xFF01411C);
  static const _orange = Color(0xFFFF8200);
  static const _black = Color(0xFF14161A);

  void _hStripes(Canvas c, Size s, List<Color> cols, [List<double>? weights]) {
    final wSum = weights?.fold<double>(0, (a, b) => a + b) ?? cols.length.toDouble();
    var y = 0.0;
    for (var i = 0; i < cols.length; i++) {
      final h = s.height * ((weights != null ? weights[i] : 1.0) / wSum);
      c.drawRect(Rect.fromLTWH(0, y, s.width, h + 0.5), Paint()..color = cols[i]);
      y += h;
    }
  }

  void _vStripes(Canvas c, Size s, List<Color> cols, [List<double>? weights]) {
    final wSum = weights?.fold<double>(0, (a, b) => a + b) ?? cols.length.toDouble();
    var x = 0.0;
    for (var i = 0; i < cols.length; i++) {
      final w = s.width * ((weights != null ? weights[i] : 1.0) / wSum);
      c.drawRect(Rect.fromLTWH(x, 0, w + 0.5, s.height), Paint()..color = cols[i]);
      x += w;
    }
  }

  void _nordic(Canvas c, Size s, Color bg, Color cross, [Color? inner]) {
    c.drawRect(Offset.zero & s, Paint()..color = bg);
    final cx = s.width * 0.34;
    final cy = s.height * 0.5;
    final t = s.height * (inner != null ? 0.22 : 0.16);
    c.drawRect(Rect.fromLTWH(cx - t / 2, 0, t, s.height), Paint()..color = cross);
    c.drawRect(Rect.fromLTWH(0, cy - t / 2, s.width, t), Paint()..color = cross);
    if (inner != null) {
      final t2 = t * 0.52;
      c.drawRect(Rect.fromLTWH(cx - t2 / 2, 0, t2, s.height), Paint()..color = inner);
      c.drawRect(Rect.fromLTWH(0, cy - t2 / 2, s.width, t2), Paint()..color = inner);
    }
  }

  void _star(Canvas c, Offset center, double r, Color color, {int points = 5}) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final rad = i.isEven ? r : r * 0.40;
      final a = (i * pi / points) - pi / 2;
      final pt = Offset(center.dx + cos(a) * rad, center.dy + sin(a) * rad);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    c.drawPath(path, Paint()..color = color);
  }

  void _crescentAndStar(Canvas c, Offset center, double r, Color fg, Color bg) {
    c.drawCircle(center, r, Paint()..color = fg);
    c.drawCircle(center + Offset(r * 0.28, 0), r * 0.80, Paint()..color = bg);
    _star(c, center + Offset(r * 1.15, 0), r * 0.46, fg);
  }

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    switch (code) {
      case 'TR':
        canvas.drawRect(Offset.zero & s, Paint()..color = _crimson);
        _crescentAndStar(canvas, Offset(w * 0.40, h * 0.5), h * 0.24, _white, _crimson);
        break;
      case 'JP':
        canvas.drawRect(Offset.zero & s, Paint()..color = _white);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), h * 0.28, Paint()..color = const Color(0xFFBC002D));
        break;
      case 'BD':
        canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF006A4E));
        canvas.drawCircle(Offset(w * 0.45, h * 0.5), h * 0.28, Paint()..color = const Color(0xFFF42A41));
        break;
      case 'FR':
        _vStripes(canvas, s, [_blue, _white, _red]);
        break;
      case 'IT':
        _vStripes(canvas, s, [_green, _white, _red]);
        break;
      case 'IE':
        _vStripes(canvas, s, [_green, _white, _orange]);
        break;
      case 'BE':
        _vStripes(canvas, s, [_black, _gold, _red]);
        break;
      case 'RO':
        _vStripes(canvas, s, [_navy, _gold, _red]);
        break;
      case 'NG':
        _vStripes(canvas, s, [_green, _white, _green]);
        break;
      case 'PE':
        _vStripes(canvas, s, [_red, _white, _red]);
        break;
      case 'MX':
        _vStripes(canvas, s, [_green, _white, _red]);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), h * 0.12, Paint()..color = const Color(0xFF7B4B2A));
        break;
      case 'CA':
        _vStripes(canvas, s, [_red, _white, _red], [1, 2, 1]);
        _star(canvas, Offset(w * 0.5, h * 0.5), h * 0.22, _red, points: 7);
        break;
      case 'DE':
        _hStripes(canvas, s, [_black, _red, _gold]);
        break;
      case 'NL':
        _hStripes(canvas, s, [_red, _white, _blue]);
        break;
      case 'RU':
        _hStripes(canvas, s, [_white, _blue, _red]);
        break;
      case 'AT':
        _hStripes(canvas, s, [_red, _white, _red]);
        break;
      case 'HU':
        _hStripes(canvas, s, [_red, _white, _green]);
        break;
      case 'BG':
        _hStripes(canvas, s, [_white, _green, _red]);
        break;
      case 'PL':
        _hStripes(canvas, s, [_white, _red]);
        break;
      case 'ID':
        _hStripes(canvas, s, [_red, _white]);
        break;
      case 'UA':
        _hStripes(canvas, s, [_blue, _gold]);
        break;
      case 'ES':
        _hStripes(canvas, s, [_red, _gold, _red], [1, 2, 1]);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.34, h * 0.5), width: w * 0.11, height: h * 0.24), const Radius.circular(3)),
          Paint()..color = _darkRed,
        );
        break;
      case 'AR':
        _hStripes(canvas, s, [_sky, _white, _sky]);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), h * 0.11, Paint()..color = _gold);
        break;
      case 'CO':
        _hStripes(canvas, s, [_gold, _blue, _red], [2, 1, 1]);
        break;
      case 'TH':
        _hStripes(canvas, s, [_red, _white, _navy, _white, _red], [1, 1, 2, 1, 1]);
        break;
      case 'IN':
        _hStripes(canvas, s, [_orange, _white, _green]);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), h * 0.11, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = _navy);
        break;
      case 'EG':
        _hStripes(canvas, s, [_red, _white, _black]);
        _star(canvas, Offset(w * 0.5, h * 0.5), h * 0.10, _gold, points: 5);
        break;
      case 'GH':
        _hStripes(canvas, s, [_red, _gold, _green]);
        _star(canvas, Offset(w * 0.5, h * 0.5), h * 0.13, _black);
        break;
      case 'ET':
        _hStripes(canvas, s, [_green, _gold, _red]);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), h * 0.16, Paint()..color = _blue);
        _star(canvas, Offset(w * 0.5, h * 0.5), h * 0.12, _gold);
        break;
      case 'AZ':
        _hStripes(canvas, s, [_sky, _red, _green]);
        _crescentAndStar(canvas, Offset(w * 0.47, h * 0.5), h * 0.11, _white, _red);
        break;
      case 'UZ':
        _hStripes(canvas, s, [_sky, _red, _white, _red, _green], [10, 1, 10, 1, 10]);
        _crescentAndStar(canvas, Offset(w * 0.14, h * 0.15), h * 0.09, _white, _sky);
        break;
      case 'SE':
        _nordic(canvas, s, _blue, _gold);
        break;
      case 'FI':
        _nordic(canvas, s, _white, _navy);
        break;
      case 'DK':
        _nordic(canvas, s, _red, _white);
        break;
      case 'NO':
        _nordic(canvas, s, _red, _white, _navy);
        break;
      case 'IS':
        _nordic(canvas, s, _blue, _white, _red);
        break;
      case 'CH':
        canvas.drawRect(Offset.zero & s, Paint()..color = _red);
        canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: h * 0.54, height: h * 0.18), Paint()..color = _white);
        canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: h * 0.18, height: h * 0.54), Paint()..color = _white);
        break;
      case 'GE':
        canvas.drawRect(Offset.zero & s, Paint()..color = _white);
        canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w, height: h * 0.18), Paint()..color = _red);
        canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: h * 0.18, height: h), Paint()..color = _red);
        for (final pt in [Offset(w * 0.22, h * 0.22), Offset(w * 0.78, h * 0.22), Offset(w * 0.22, h * 0.78), Offset(w * 0.78, h * 0.78)]) {
          canvas.drawRect(Rect.fromCenter(center: pt, width: h * 0.14, height: h * 0.045), Paint()..color = _red);
          canvas.drawRect(Rect.fromCenter(center: pt, width: h * 0.045, height: h * 0.14), Paint()..color = _red);
        }
        break;
      case 'GB':
        canvas.drawRect(Offset.zero & s, Paint()..color = _navy);
        final wp = Paint()..color = _white..strokeWidth = h * 0.18;
        final rp = Paint()..color = _red..strokeWidth = h * 0.09;
        canvas.drawLine(Offset.zero, Offset(w, h), wp);
        canvas.drawLine(Offset(w, 0), Offset(0, h), wp);
        canvas.drawLine(Offset.zero, Offset(w, h), rp);
        canvas.drawLine(Offset(w, 0), Offset(0, h), rp);
        canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w, height: h * 0.28), Paint()..color = _white);
        canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: h * 0.28, height: h), Paint()..color = _white);
        canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w, height: h * 0.16), Paint()..color = _red);
        canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: h * 0.16, height: h), Paint()..color = _red);
        break;
      case 'US':
        _hStripes(canvas, s, [for (var i = 0; i < 13; i++) i.isEven ? _red : _white]);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.42, h * (7 / 13)), Paint()..color = _navy);
        for (var r = 0; r < 4; r++) {
          for (var c = 0; c < 5; c++) {
            canvas.drawCircle(Offset(w * (0.06 + c * 0.075), h * (0.08 + r * 0.12)), 2.2, Paint()..color = _white);
          }
        }
        break;
      case 'GR':
        _hStripes(canvas, s, [for (var i = 0; i < 9; i++) i.isEven ? _blue : _white]);
        final cb = h * (5 / 9);
        canvas.drawRect(Rect.fromLTWH(0, 0, cb, cb), Paint()..color = _blue);
        canvas.drawRect(Rect.fromLTWH(cb * 0.4, 0, cb * 0.2, cb), Paint()..color = _white);
        canvas.drawRect(Rect.fromLTWH(0, cb * 0.4, cb, cb * 0.2), Paint()..color = _white);
        break;
      case 'CL':
        _hStripes(canvas, s, [_white, _red]);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.34, h * 0.5), Paint()..color = _navy);
        _star(canvas, Offset(w * 0.17, h * 0.25), h * 0.12, _white);
        break;
      case 'MY':
        _hStripes(canvas, s, [for (var i = 0; i < 14; i++) i.isEven ? _red : _white]);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.48, h * 0.57), Paint()..color = _navy);
        _crescentAndStar(canvas, Offset(w * 0.20, h * 0.28), h * 0.15, _gold, _navy);
        break;
      case 'SG':
        _hStripes(canvas, s, [_red, _white]);
        _crescentAndStar(canvas, Offset(w * 0.20, h * 0.25), h * 0.15, _white, _red);
        break;
      case 'BR':
        canvas.drawRect(Offset.zero & s, Paint()..color = _green);
        final diamond = Path()
          ..moveTo(w * 0.5, h * 0.12)
          ..lineTo(w * 0.88, h * 0.5)
          ..lineTo(w * 0.5, h * 0.88)
          ..lineTo(w * 0.12, h * 0.5)
          ..close();
        canvas.drawPath(diamond, Paint()..color = _gold);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), h * 0.21, Paint()..color = _navy);
        canvas.drawLine(Offset(w * 0.36, h * 0.46), Offset(w * 0.64, h * 0.54), Paint()..color = _white..strokeWidth = 3.2);
        break;
      case 'CN':
        canvas.drawRect(Offset.zero & s, Paint()..color = _red);
        _star(canvas, Offset(w * 0.18, h * 0.28), h * 0.14, _gold);
        for (final pt in [Offset(w * 0.33, h * 0.14), Offset(w * 0.38, h * 0.24), Offset(w * 0.38, h * 0.36), Offset(w * 0.33, h * 0.46)]) {
          _star(canvas, pt, h * 0.05, _gold);
        }
        break;
      case 'VN':
        canvas.drawRect(Offset.zero & s, Paint()..color = _red);
        _star(canvas, Offset(w * 0.5, h * 0.5), h * 0.26, _gold);
        break;
      case 'MA':
        canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFC1272D));
        _star(canvas, Offset(w * 0.5, h * 0.5), h * 0.22, _green);
        break;
      case 'TN':
        canvas.drawRect(Offset.zero & s, Paint()..color = _crimson);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), h * 0.25, Paint()..color = _white);
        _crescentAndStar(canvas, Offset(w * 0.49, h * 0.5), h * 0.14, _crimson, _white);
        break;
      case 'PK':
        _vStripes(canvas, s, [_white, _darkGreen], [1, 3]);
        _crescentAndStar(canvas, Offset(w * 0.60, h * 0.5), h * 0.22, _white, _darkGreen);
        break;
      case 'SA':
        canvas.drawRect(Offset.zero & s, Paint()..color = _darkGreen);
        canvas.drawLine(Offset(w * 0.26, h * 0.64), Offset(w * 0.74, h * 0.64), Paint()..color = _white..strokeWidth = 3.2..strokeCap = StrokeCap.round);
        canvas.drawLine(Offset(w * 0.30, h * 0.44), Offset(w * 0.70, h * 0.44), Paint()..color = _white..strokeWidth = 4.0..strokeCap = StrokeCap.round);
        break;
      case 'KR':
        canvas.drawRect(Offset.zero & s, Paint()..color = _white);
        canvas.drawArc(Rect.fromCircle(center: Offset(w * 0.5, h * 0.5), radius: h * 0.22), pi, pi, true, Paint()..color = _red);
        canvas.drawArc(Rect.fromCircle(center: Offset(w * 0.5, h * 0.5), radius: h * 0.22), 0, pi, true, Paint()..color = _blue);
        for (final pt in [Offset(w * 0.22, h * 0.24), Offset(w * 0.78, h * 0.24), Offset(w * 0.22, h * 0.76), Offset(w * 0.78, h * 0.76)]) {
          canvas.drawRect(Rect.fromCenter(center: pt, width: w * 0.12, height: h * 0.09), Paint()..color = _black);
        }
        break;
      case 'CZ':
        _hStripes(canvas, s, [_white, _red]);
        final tri = Path()..moveTo(0, 0)..lineTo(w * 0.48, h * 0.5)..lineTo(0, h)..close();
        canvas.drawPath(tri, Paint()..color = _navy);
        break;
      case 'PH':
        _hStripes(canvas, s, [_blue, _red]);
        final tri = Path()..moveTo(0, 0)..lineTo(w * 0.44, h * 0.5)..lineTo(0, h)..close();
        canvas.drawPath(tri, Paint()..color = _white);
        _star(canvas, Offset(w * 0.16, h * 0.5), h * 0.12, _gold, points: 8);
        break;
      case 'CU':
        _hStripes(canvas, s, [_blue, _white, _blue, _white, _blue]);
        final tri = Path()..moveTo(0, 0)..lineTo(w * 0.44, h * 0.5)..lineTo(0, h)..close();
        canvas.drawPath(tri, Paint()..color = _red);
        _star(canvas, Offset(w * 0.15, h * 0.5), h * 0.12, _white);
        break;
      case 'PT':
        _vStripes(canvas, s, [_green, _red], [2, 3]);
        canvas.drawCircle(Offset(w * 0.40, h * 0.5), h * 0.18, Paint()..color = _gold);
        canvas.drawCircle(Offset(w * 0.40, h * 0.5), h * 0.11, Paint()..color = _red);
        break;
      case 'JM':
        canvas.drawRect(Offset.zero & s, Paint()..color = _green);
        final leftTri = Path()..moveTo(0, 0)..lineTo(w * 0.48, h * 0.5)..lineTo(0, h)..close();
        final rightTri = Path()..moveTo(w, 0)..lineTo(w * 0.52, h * 0.5)..lineTo(w, h)..close();
        canvas.drawPath(leftTri, Paint()..color = _black);
        canvas.drawPath(rightTri, Paint()..color = _black);
        final gp = Paint()..color = _gold..strokeWidth = h * 0.14;
        canvas.drawLine(Offset.zero, Offset(w, h), gp);
        canvas.drawLine(Offset(w, 0), Offset(0, h), gp);
        break;
      case 'ZA':
        _hStripes(canvas, s, [_red, _white, _navy], [2, 1, 2]);
        final yPath = Path()
          ..moveTo(0, 0)..lineTo(w * 0.42, h * 0.5)..lineTo(0, h)
          ..lineTo(0, h * 0.85)..lineTo(w * 0.30, h * 0.5)..lineTo(0, h * 0.15)..close();
        canvas.drawPath(yPath, Paint()..color = _gold);
        final blackTri = Path()..moveTo(0, h * 0.18)..lineTo(w * 0.27, h * 0.5)..lineTo(0, h * 0.82)..close();
        canvas.drawPath(blackTri, Paint()..color = _black);
        canvas.drawLine(Offset(w * 0.36, h * 0.5), Offset(w, h * 0.5), Paint()..color = _green..strokeWidth = h * 0.18);
        canvas.drawLine(Offset(0, 0), Offset(w * 0.40, h * 0.5), Paint()..color = _green..strokeWidth = h * 0.14);
        canvas.drawLine(Offset(0, h), Offset(w * 0.40, h * 0.5), Paint()..color = _green..strokeWidth = h * 0.14);
        break;
      case 'KE':
        _hStripes(canvas, s, [_black, _white, _darkRed, _white, _green], [6, 1, 6, 1, 6]);
        canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.14, height: h * 0.42), Paint()..color = _darkRed);
        canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.05, height: h * 0.30), Paint()..color = _white);
        break;
      case 'AE':
        _hStripes(canvas, s, [_green, _white, _black]);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.26, h), Paint()..color = _red);
        break;
      case 'QA':
        canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF8D1B3D));
        final qPath = Path()..moveTo(0, 0)..lineTo(w * 0.28, 0);
        for (var i = 0; i < 9; i++) {
          qPath.lineTo(w * 0.36, h * (i + 0.5) / 9);
          qPath.lineTo(w * 0.28, h * (i + 1) / 9);
        }
        qPath..lineTo(0, h)..close();
        canvas.drawPath(qPath, Paint()..color = _white);
        break;
      case 'KZ':
        canvas.drawRect(Offset.zero & s, Paint()..color = _sky);
        canvas.drawRect(Rect.fromLTWH(w * 0.06, h * 0.10, w * 0.05, h * 0.80), Paint()..color = _gold);
        canvas.drawCircle(Offset(w * 0.54, h * 0.44), h * 0.15, Paint()..color = _gold);
        canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.54, h * 0.64), width: w * 0.32, height: h * 0.18), 0, pi, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 3.5..color = _gold);
        break;
      case 'AU':
      case 'NZ':
        canvas.drawRect(Offset.zero & s, Paint()..color = _navy);
        // Canton Union Jack mini
        final cw = w * 0.46, ch = h * 0.48;
        canvas.drawLine(Offset.zero, Offset(cw, ch), Paint()..color = _white..strokeWidth = 4);
        canvas.drawLine(Offset(cw, 0), Offset(0, ch), Paint()..color = _white..strokeWidth = 4);
        canvas.drawRect(Rect.fromCenter(center: Offset(cw * 0.5, ch * 0.5), width: cw, height: ch * 0.24), Paint()..color = _white);
        canvas.drawRect(Rect.fromCenter(center: Offset(cw * 0.5, ch * 0.5), width: ch * 0.24, height: ch), Paint()..color = _white);
        canvas.drawRect(Rect.fromCenter(center: Offset(cw * 0.5, ch * 0.5), width: cw, height: ch * 0.14), Paint()..color = _red);
        canvas.drawRect(Rect.fromCenter(center: Offset(cw * 0.5, ch * 0.5), width: ch * 0.14, height: ch), Paint()..color = _red);
        final starColor = code == 'NZ' ? _red : _white;
        if (code == 'AU') {
          _star(canvas, Offset(w * 0.23, h * 0.74), h * 0.11, _white, points: 7);
        }
        for (final pt in [Offset(w * 0.75, h * 0.22), Offset(w * 0.66, h * 0.46), Offset(w * 0.85, h * 0.42), Offset(w * 0.75, h * 0.78)]) {
          _star(canvas, pt, h * 0.065, starColor);
        }
        break;
      case 'IL':
        canvas.drawRect(Offset.zero & s, Paint()..color = _white);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.12, w, h * 0.12), Paint()..color = _blue);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.76, w, h * 0.12), Paint()..color = _blue);
        final hexR = h * 0.18;
        final c = Offset(w * 0.5, h * 0.5);
        final t1 = Path()
          ..moveTo(c.dx, c.dy - hexR)
          ..lineTo(c.dx + hexR * 0.86, c.dy + hexR * 0.5)
          ..lineTo(c.dx - hexR * 0.86, c.dy + hexR * 0.5)
          ..close();
        final t2 = Path()
          ..moveTo(c.dx, c.dy + hexR)
          ..lineTo(c.dx + hexR * 0.86, c.dy - hexR * 0.5)
          ..lineTo(c.dx - hexR * 0.86, c.dy - hexR * 0.5)
          ..close();
        final sp = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..color = _blue;
        canvas.drawPath(t1, sp);
        canvas.drawPath(t2, sp);
        break;
      default:
        _hStripes(canvas, s, [_blue, _white, _red]);
    }
    // Subtle satin sheen overlay
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.14),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.12),
          ],
        ).createShader(Offset.zero & s),
    );
  }

  @override
  bool shouldRepaint(covariant _FlagVisualPainter old) => old.code != code;
}

class _MusicStaffPainter extends CustomPainter {
  final String clef;
  final List<String> notes;
  final bool isChord;
  final Color accent;

  _MusicStaffPainter({
    required this.clef,
    required this.notes,
    required this.isChord,
    required this.accent,
  });

  static const _noteOrder = {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6};

  int _diatonicStep(String raw) {
    final clean = raw.trim().toUpperCase();
    if (clean.isEmpty) return 28;
    final letter = clean[0];
    final octMatch = RegExp(r'\d').firstMatch(clean);
    final oct = octMatch != null ? int.parse(octMatch.group(0)!) : 4;
    return oct * 7 + (_noteOrder[letter] ?? 0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final lineGap = min(size.height * 0.13, 18.0);
    final topLine = (size.height - lineGap * 4) / 2;
    final left = 16.0;
    final right = size.width - 16.0;

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.52)
      ..strokeWidth = 1.3;
    for (var i = 0; i < 5; i++) {
      final y = topLine + i * lineGap;
      canvas.drawLine(Offset(left, y), Offset(right, y), linePaint);
    }
    // Bar lines
    canvas.drawLine(Offset(left, topLine), Offset(left, topLine + lineGap * 4), linePaint..strokeWidth = 2.0);
    canvas.drawLine(Offset(right, topLine), Offset(right, topLine + lineGap * 4), linePaint..strokeWidth = 2.5);

    // Clef badge
    final clefLabel = clef == 'bass' ? 'Fa (𝄢)' : 'Sol (𝄞)';
    final clefTp = TextPainter(
      text: TextSpan(
        text: clef == 'bass' ? '𝄢' : '𝄞',
        style: TextStyle(
          fontSize: lineGap * 3.1,
          color: accent,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    clefTp.paint(canvas, Offset(left + 8, topLine - lineGap * 0.45));

    final tagTp = TextPainter(
      text: TextSpan(
        text: clefLabel,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: accent.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tagTp.paint(canvas, Offset(left + 4, size.height - 14));

    if (notes.isEmpty) return;

    // Bottom line step: Treble = E4 (4*7+2 = 30), Bass = G2 (2*7+4 = 18)
    final bottomStep = clef == 'bass' ? 18 : 30;
    final bottomY = topLine + lineGap * 4;
    final startX = left + 68;
    final availW = max(right - startX - 24, 40.0);

    for (var i = 0; i < notes.length; i++) {
      final raw = notes[i];
      final step = _diatonicStep(raw);
      final delta = step - bottomStep; // 0 = bottom line, 8 = top line
      final y = bottomY - delta * (lineGap / 2);
      final x = isChord
          ? startX + availW * 0.45
          : (notes.length == 1
              ? startX + availW * 0.45
              : startX + availW * (i / (notes.length - 1)));

      // Ledger lines below/above staff
      if (delta <= -2) {
        for (var s = -2; s >= delta; s -= 2) {
          final ly = bottomY - s * (lineGap / 2);
          canvas.drawLine(Offset(x - 12, ly), Offset(x + 12, ly), Paint()..color = Colors.white70..strokeWidth = 1.4);
        }
      } else if (delta >= 10) {
        for (var s = 10; s <= delta; s += 2) {
          final ly = bottomY - s * (lineGap / 2);
          canvas.drawLine(Offset(x - 12, ly), Offset(x + 12, ly), Paint()..color = Colors.white70..strokeWidth = 1.4);
        }
      }

      // Accidental (# or b)
      if (raw.contains('#') || raw.contains('b')) {
        final acc = raw.contains('#') ? '♯' : '♭';
        final accTp = TextPainter(
          text: TextSpan(
            text: acc,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF4CE0D2)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        accTp.paint(canvas, Offset(x - 21, y - accTp.height / 2));
      }

      // Tilted notehead
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(-0.28);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: lineGap * 1.15, height: lineGap * 0.82),
        Paint()..color = accent,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: lineGap * 1.15, height: lineGap * 0.82),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = Colors.white,
      );
      canvas.restore();

      // Stem
      if (!isChord || i == notes.length - 1) {
        final stemUp = delta < 4;
        final sx = stemUp ? x + lineGap * 0.52 : x - lineGap * 0.52;
        final syEnd = stemUp ? y - lineGap * 2.5 : y + lineGap * 2.5;
        canvas.drawLine(
          Offset(sx, y),
          Offset(sx, syEnd),
          Paint()..color = Colors.white..strokeWidth = 1.8..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MusicStaffPainter old) =>
      old.clef != clef || old.notes != notes || old.isChord != isChord;
}

class _CoordPlanePainter extends CustomPainter {
  final double minX, maxX, minY, maxY;
  final List<DiagramElement> elements;
  final Color accent;

  _CoordPlanePainter({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.elements,
    required this.accent,
  });

  Color _color(String? name) => switch (name?.toLowerCase()) {
        'mint' => const Color(0xFF4CE0D2),
        'blue' => const Color(0xFF5AB2FF),
        'gold' => const Color(0xFFF6C453),
        'pink' => const Color(0xFFFF7BAC),
        'violet' => const Color(0xFFB88CFF),
        _ => accent,
      };

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 20.0;
    final plotW = max(size.width - pad * 2, 40.0);
    final plotH = max(size.height - pad * 2, 40.0);
    final side = min(plotW, plotH);
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;

    Offset mapPt(double x, double y) {
      final nx = (x - minX) / max(0.001, maxX - minX);
      final ny = (y - minY) / max(0.001, maxY - minY);
      return Offset(left + nx * side, top + (1 - ny) * side);
    }

    // Background grid
    final gridP = Paint()..color = Colors.white.withValues(alpha: 0.11)..strokeWidth = 0.8;
    for (var gx = minX.ceil(); gx <= maxX.floor(); gx++) {
      final pTop = mapPt(gx.toDouble(), maxY);
      final pBot = mapPt(gx.toDouble(), minY);
      canvas.drawLine(pTop, pBot, gridP);
    }
    for (var gy = minY.ceil(); gy <= maxY.floor(); gy++) {
      final pLeft = mapPt(minX, gy.toDouble());
      final pRight = mapPt(maxX, gy.toDouble());
      canvas.drawLine(pLeft, pRight, gridP);
    }

    // Axes
    final axisP = Paint()..color = Colors.white.withValues(alpha: 0.55)..strokeWidth = 1.6;
    if (minY <= 0 && maxY >= 0) {
      final a = mapPt(minX, 0), b = mapPt(maxX, 0);
      canvas.drawLine(a, b, axisP);
      final xTp = TextPainter(
        text: const TextSpan(text: 'x', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white70)),
        textDirection: TextDirection.ltr,
      )..layout();
      xTp.paint(canvas, Offset(b.dx + 4, b.dy - 7));
    }
    if (minX <= 0 && maxX >= 0) {
      final a = mapPt(0, minY), b = mapPt(0, maxY);
      canvas.drawLine(a, b, axisP);
      final yTp = TextPainter(
        text: const TextSpan(text: 'y', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white70)),
        textDirection: TextDirection.ltr,
      )..layout();
      yTp.paint(canvas, Offset(b.dx + 4, b.dy - 10));
    }

    // Sparse tick numbers
    final step = ((maxX - minX) / 5).round().clamp(1, 5);
    for (var gx = minX.ceil(); gx <= maxX.floor(); gx += step) {
      if (gx == 0) continue;
      final pt = mapPt(gx.toDouble(), 0.clamp(minY, maxY).toDouble());
      final tp = TextPainter(
        text: TextSpan(text: '$gx', style: TextStyle(fontSize: 8.5, color: Colors.white.withValues(alpha: 0.55))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pt.dx - tp.width / 2, pt.dy + 3));
    }
    for (var gy = minY.ceil(); gy <= maxY.floor(); gy += step) {
      if (gy == 0) continue;
      final pt = mapPt(0.clamp(minX, maxX).toDouble(), gy.toDouble());
      final tp = TextPainter(
        text: TextSpan(text: '$gy', style: TextStyle(fontSize: 8.5, color: Colors.white.withValues(alpha: 0.55))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pt.dx - tp.width - 4, pt.dy - tp.height / 2));
    }

    // Elements
    for (final el in elements) {
      final col = _color(el.color);
      final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.3..color = col..strokeCap = StrokeCap.round;
      final fill = Paint()..color = col.withValues(alpha: 0.22);

      if (el.shape == 'polygon' && el.label != null) {
        final rawPts = el.label!.split(';');
        final path = Path();
        var first = true;
        for (final token in rawPts) {
          final xy = token.split(',');
          if (xy.length != 2) continue;
          final px = double.tryParse(xy[0].trim());
          final py = double.tryParse(xy[1].trim());
          if (px == null || py == null) continue;
          final m = mapPt(px, py);
          if (first) {
            path.moveTo(m.dx, m.dy);
            first = false;
          } else {
            path.lineTo(m.dx, m.dy);
          }
        }
        path.close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
      } else if (el.shape == 'line' || el.shape == 'arrow') {
        final p1 = mapPt(el.x, el.y);
        final p2 = mapPt(el.endX ?? el.x, el.endY ?? el.y);
        canvas.drawLine(p1, p2, stroke);
        if (el.shape == 'arrow') {
          final a = atan2(p2.dy - p1.dy, p2.dx - p1.dx);
          const head = 8.5;
          canvas.drawLine(p2, Offset(p2.dx - head * cos(a - 0.45), p2.dy - head * sin(a - 0.45)), stroke);
          canvas.drawLine(p2, Offset(p2.dx - head * cos(a + 0.45), p2.dy - head * sin(a + 0.45)), stroke);
        }
        if (el.label != null && el.label!.isNotEmpty) {
          final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
          final tp = TextPainter(
            text: TextSpan(text: el.label!, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: col)),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(mid.dx + 4, mid.dy - tp.height - 2));
        }
      } else if (el.shape == 'circle') {
        final c = mapPt(el.x, el.y);
        final rPx = ((el.width ?? 1.0) / max(0.001, maxX - minX)) * side;
        canvas.drawCircle(c, rPx, fill);
        canvas.drawCircle(c, rPx, stroke);
      } else if (el.shape == 'point') {
        final p = mapPt(el.x, el.y);
        canvas.drawCircle(p, 5.0, Paint()..color = col);
        canvas.drawCircle(p, 2.2, Paint()..color = Colors.white);
        if (el.label != null && el.label!.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: el.label!,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final dx = p.dx + tp.width + 8 > size.width ? p.dx - tp.width - 6 : p.dx + 6;
          final dy = p.dy - tp.height - 2 < 2 ? p.dy + 5 : p.dy - tp.height - 2;
          tp.paint(canvas, Offset(dx, dy));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CoordPlanePainter old) =>
      old.elements != elements || old.minX != minX || old.maxX != maxX;
}

class _AtomVisualPainter extends CustomPainter {
  final int protons;
  final int neutrons;
  final List<int> shells;
  final String centerLabel;
  final Color accent;

  _AtomVisualPainter({
    required this.protons,
    required this.neutrons,
    required this.shells,
    required this.centerLabel,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = min(size.width, size.height) * 0.45;
    final shellCount = max(1, shells.length);
    final nucR = max(18.0, maxR * 0.24);

    // Orbits & electrons
    for (var sIdx = 0; sIdx < shells.length; sIdx++) {
      final frac = (sIdx + 1) / shellCount;
      final orbitR = nucR + (maxR - nucR) * frac;
      canvas.drawCircle(
        center,
        orbitR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF4CE0D2).withValues(alpha: 0.35),
      );

      final count = shells[sIdx];
      for (var e = 0; e < count; e++) {
        final angle = -pi / 2 + (2 * pi * e / max(1, count)) + sIdx * 0.35;
        final pos = Offset(center.dx + cos(angle) * orbitR, center.dy + sin(angle) * orbitR);
        canvas.drawCircle(pos, 6.0, Paint()..color = const Color(0xFF4CE0D2).withValues(alpha: 0.28));
        canvas.drawCircle(pos, 3.6, Paint()..color = const Color(0xFF7CEEFF));
        canvas.drawCircle(pos, 1.5, Paint()..color = Colors.white);
      }
    }

    // Nucleus glow
    canvas.drawCircle(
      center,
      nucR + 5,
      Paint()..color = accent.withValues(alpha: 0.20),
    );
    canvas.drawCircle(
      center,
      nucR,
      Paint()
        ..shader = RadialGradient(
          colors: [accent, const Color(0xFFC47A10)],
        ).createShader(Rect.fromCircle(center: center, radius: nucR)),
    );
    canvas.drawCircle(
      center,
      nucR,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = Colors.white70,
    );

    final symTp = TextPainter(
      text: TextSpan(
        text: centerLabel,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w900,
          color: Color(0xFF061028),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    symTp.paint(canvas, Offset(center.dx - symTp.width / 2, center.dy - symTp.height / 2 - 5));

    final pnTp = TextPainter(
      text: TextSpan(
        text: '${protons}p ${neutrons}n',
        style: const TextStyle(
          fontSize: 8.2,
          fontWeight: FontWeight.w900,
          color: Color(0xFF061028),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    pnTp.paint(canvas, Offset(center.dx - pnTp.width / 2, center.dy + 4));
  }

  @override
  bool shouldRepaint(covariant _AtomVisualPainter old) =>
      old.protons != protons || old.neutrons != neutrons || old.shells != shells || old.centerLabel != centerLabel;
}

class _PatternMatrixPainter extends CustomPainter {
  final List<List<String>> rows;
  final Color accent;

  _PatternMatrixPainter({required this.rows, required this.accent});

  Color _col(String name) => switch (name) {
        'gold' => const Color(0xFFF6C453),
        'cyan' => const Color(0xFF4CE0D2),
        'coral' => const Color(0xFFFF7B89),
        'mint' => const Color(0xFF5CE09B),
        'violet' => const Color(0xFFC5A3FF),
        _ => Colors.white,
      };

  void _drawShape(Canvas c, Offset center, double r, String shape, Color col, double rotDeg, String fill) {
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(rotDeg * pi / 180);

    final pFill = Paint()..color = fill == 'solid' ? col : col.withValues(alpha: 0.12);
    final pStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = col;

    Path? poly;
    switch (shape) {
      case 'circle':
        c.drawCircle(Offset.zero, r, pFill);
        c.drawCircle(Offset.zero, r, pStroke);
        break;
      case 'square':
        final rect = Rect.fromCenter(center: Offset.zero, width: r * 1.7, height: r * 1.7);
        c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), pFill);
        c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), pStroke);
        break;
      case 'triangle':
        poly = Path()
          ..moveTo(0, -r)
          ..lineTo(r * 0.92, r * 0.78)
          ..lineTo(-r * 0.92, r * 0.78)
          ..close();
        break;
      case 'diamond':
        poly = Path()
          ..moveTo(0, -r)
          ..lineTo(r * 0.82, 0)
          ..lineTo(0, r)
          ..lineTo(-r * 0.82, 0)
          ..close();
        break;
      case 'hexagon':
        poly = Path();
        for (var i = 0; i < 6; i++) {
          final a = i * pi / 3 - pi / 2;
          final pt = Offset(cos(a) * r, sin(a) * r);
          if (i == 0) {
            poly.moveTo(pt.dx, pt.dy);
          } else {
            poly.lineTo(pt.dx, pt.dy);
          }
        }
        poly.close();
        break;
      case 'star':
        poly = Path();
        for (var i = 0; i < 10; i++) {
          final rad = i.isEven ? r : r * 0.44;
          final a = i * pi / 5 - pi / 2;
          final pt = Offset(cos(a) * rad, sin(a) * rad);
          if (i == 0) {
            poly.moveTo(pt.dx, pt.dy);
          } else {
            poly.lineTo(pt.dx, pt.dy);
          }
        }
        poly.close();
        break;
      case 'arrow':
        poly = Path()
          ..moveTo(0, -r)
          ..lineTo(r * 0.78, 0)
          ..lineTo(r * 0.30, 0)
          ..lineTo(r * 0.30, r * 0.92)
          ..lineTo(-r * 0.30, r * 0.92)
          ..lineTo(-r * 0.30, 0)
          ..lineTo(-r * 0.78, 0)
          ..close();
        break;
      case 'cross':
        c.drawLine(Offset(0, -r), Offset(0, r), Paint()..color = col..strokeWidth = 3.2..strokeCap = StrokeCap.round);
        c.drawLine(Offset(-r, 0), Offset(r, 0), Paint()..color = col..strokeWidth = 3.2..strokeCap = StrokeCap.round);
        break;
      default:
        c.drawCircle(Offset.zero, r, pFill);
        c.drawCircle(Offset.zero, r, pStroke);
    }
    if (poly != null) {
      c.drawPath(poly, pFill);
      c.drawPath(poly, pStroke);
    }
    if (fill == 'dot') {
      c.drawCircle(Offset.zero, r * 0.30, Paint()..color = col);
    }
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / 3;
    final cellH = size.height / 3;
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        final rect = Rect.fromLTWH(c * cellW + 3, r * cellH + 3, cellW - 6, cellH - 6);
        final spec = (r < rows.length && c < rows[r].length) ? rows[r][c] : '?';
        final isMissing = spec.trim() == '?';
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(10));
        canvas.drawRRect(
          rr,
          Paint()
            ..color = isMissing
                ? accent.withValues(alpha: 0.18)
                : const Color(0xFF0C164A),
        );
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isMissing ? 2.0 : 1.1
            ..color = isMissing ? accent : Colors.white.withValues(alpha: 0.18),
        );

        if (isMissing) {
          final tp = TextPainter(
            text: TextSpan(
              text: '?',
              style: TextStyle(fontSize: cellH * 0.48, fontWeight: FontWeight.w900, color: accent),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
        } else {
          final parts = spec.split(':');
          final shape = parts.isNotEmpty ? parts[0] : 'circle';
          final count = parts.length > 1 ? (int.tryParse(parts[1]) ?? 1).clamp(1, 4) : 1;
          final col = _col(parts.length > 2 ? parts[2] : 'gold');
          final rot = parts.length > 3 ? (double.tryParse(parts[3]) ?? 0.0) : 0.0;
          final fill = parts.length > 4 ? parts[4] : 'solid';
          final baseR = min(rect.width, rect.height) * (count == 1 ? 0.30 : (count == 2 ? 0.18 : 0.15));
          final offsets = switch (count) {
            1 => [rect.center],
            2 => [rect.center + Offset(-baseR * 1.15, 0), rect.center + Offset(baseR * 1.15, 0)],
            3 => [
                rect.center + Offset(0, -baseR * 0.95),
                rect.center + Offset(-baseR * 1.1, baseR * 0.9),
                rect.center + Offset(baseR * 1.1, baseR * 0.9),
              ],
            _ => [
                rect.center + Offset(-baseR * 1.05, -baseR * 1.05),
                rect.center + Offset(baseR * 1.05, -baseR * 1.05),
                rect.center + Offset(-baseR * 1.05, baseR * 1.05),
                rect.center + Offset(baseR * 1.05, baseR * 1.05),
              ],
          };
          for (final pos in offsets) {
            _drawShape(canvas, pos, baseR, shape, col, rot, fill);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternMatrixPainter old) => old.rows != rows;
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

class _CircuitVisualPainter extends CustomPainter {
  final String mode; // logic, series, parallel
  final List<String> labels;
  final List<double> values;
  final Color accent;

  _CircuitVisualPainter({
    required this.mode,
    required this.labels,
    required this.values,
    required this.accent,
  });

  void _paintText(Canvas c, String text, Offset center, Color col, {double size = 11.5}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: col),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawGateBox(Canvas c, Rect rect, String gateName, Color col) {
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    c.drawRRect(rr, Paint()..color = const Color(0xFF101D5C));
    c.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0..color = col);
    _paintText(c, gateName, rect.center, col, size: 12);
    if (gateName == 'NAND' || gateName == 'NOR' || gateName == 'NOT') {
      c.drawCircle(
        Offset(rect.right + 5, rect.center.dy),
        4.5,
        Paint()..color = const Color(0xFF0A1240),
      );
      c.drawCircle(
        Offset(rect.right + 5, rect.center.dy),
        4.5,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1.8..color = col,
      );
    }
  }

  void _drawBitNode(Canvas c, Offset pos, String label, String bit) {
    final isOne = bit == '1';
    final col = isOne ? const Color(0xFF4BE085) : const Color(0xFFFF7B89);
    c.drawCircle(pos, 15, Paint()..color = col.withValues(alpha: 0.20));
    c.drawCircle(pos, 15, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.8..color = col);
    _paintText(c, '$label=$bit', pos, Colors.white, size: 10.2);
  }

  void _drawResistor(Canvas c, Offset a, Offset b, String label, Color col) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 10) return;
    final ux = dx / len, uy = dy / len;
    final px = -uy, py = ux;
    final start = Offset(a.dx + ux * len * 0.22, a.dy + uy * len * 0.22);
    final end = Offset(a.dx + ux * len * 0.78, a.dy + uy * len * 0.78);
    final wire = Paint()..color = const Color(0xFF7CEEFF)..strokeWidth = 2.0;
    c.drawLine(a, start, wire);
    c.drawLine(end, b, wire);
    final zig = Path()..moveTo(start.dx, start.dy);
    const peaks = 6;
    for (var i = 1; i <= peaks; i++) {
      final t = i / (peaks + 1);
      final bx = start.dx + (end.dx - start.dx) * t;
      final by = start.dy + (end.dy - start.dy) * t;
      final amp = i.isOdd ? 7.0 : -7.0;
      zig.lineTo(bx + px * amp, by + py * amp);
    }
    zig.lineTo(end.dx, end.dy);
    c.drawPath(zig, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = col);
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    _paintText(c, label, mid + Offset(px * 16, py * 16 - 4), Colors.white, size: 10.5);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final wire = Paint()..color = const Color(0xFF4CE0D2).withValues(alpha: 0.78)..strokeWidth = 2.2;
    if (mode == 'logic') {
      final isTwoStage = labels.length >= 5;
      final g1 = labels.isNotEmpty ? labels[0] : 'AND';
      final a = labels.length > 1 ? labels[1] : '1';
      final b = labels.length > 2 ? labels[2] : '0';

      if (!isTwoStage) {
        final gateRect = Rect.fromCenter(center: Offset(size.width * 0.50, size.height * 0.50), width: 78, height: 54);
        final outPos = Offset(size.width * 0.84, size.height * 0.50);
        if (g1 == 'NOT') {
          final inA = Offset(size.width * 0.16, size.height * 0.50);
          canvas.drawLine(Offset(inA.dx + 15, inA.dy), Offset(gateRect.left, gateRect.center.dy), wire);
          _drawBitNode(canvas, inA, 'A', a);
        } else {
          final inA = Offset(size.width * 0.16, size.height * 0.30);
          final inB = Offset(size.width * 0.16, size.height * 0.70);
          canvas.drawLine(Offset(inA.dx + 15, inA.dy), Offset(gateRect.left, gateRect.top + 14), wire);
          canvas.drawLine(Offset(inB.dx + 15, inB.dy), Offset(gateRect.left, gateRect.bottom - 14), wire);
          _drawBitNode(canvas, inA, 'A', a);
          _drawBitNode(canvas, inB, 'B', b);
        }
        canvas.drawLine(Offset(gateRect.right + 8, gateRect.center.dy), Offset(outPos.dx - 17, outPos.dy), wire..color = accent);
        _drawGateBox(canvas, gateRect, g1, accent);
        canvas.drawCircle(outPos, 17, Paint()..color = accent.withValues(alpha: 0.24));
        canvas.drawCircle(outPos, 17, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0..color = accent);
        _paintText(canvas, '?', outPos, accent, size: 16);
      } else {
        final g2 = labels[3];
        final cBit = labels[4];
        final r1 = Rect.fromCenter(center: Offset(size.width * 0.37, size.height * 0.36), width: 64, height: 42);
        final r2 = Rect.fromCenter(center: Offset(size.width * 0.67, size.height * 0.54), width: 64, height: 42);
        final inA = Offset(size.width * 0.12, size.height * 0.22);
        final inB = Offset(size.width * 0.12, size.height * 0.50);
        final inC = Offset(size.width * 0.12, size.height * 0.78);
        final outPos = Offset(size.width * 0.90, size.height * 0.54);

        canvas.drawLine(Offset(inA.dx + 15, inA.dy), Offset(r1.left, r1.top + 11), wire);
        canvas.drawLine(Offset(inB.dx + 15, inB.dy), Offset(r1.left, r1.bottom - 11), wire);
        canvas.drawLine(Offset(r1.right + 6, r1.center.dy), Offset(r2.left, r2.top + 11), wire);
        canvas.drawLine(Offset(inC.dx + 15, inC.dy), Offset(r2.left, r2.bottom - 11), wire);
        canvas.drawLine(Offset(r2.right + 6, r2.center.dy), Offset(outPos.dx - 15, outPos.dy), wire..color = accent);

        _drawBitNode(canvas, inA, 'A', a);
        _drawBitNode(canvas, inB, 'B', b);
        _drawBitNode(canvas, inC, 'C', cBit);
        _drawGateBox(canvas, r1, g1, const Color(0xFF4CE0D2));
        _drawGateBox(canvas, r2, g2, accent);
        canvas.drawCircle(outPos, 15, Paint()..color = accent.withValues(alpha: 0.24));
        canvas.drawCircle(outPos, 15, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0..color = accent);
        _paintText(canvas, '?', outPos, accent, size: 15);
      }
      return;
    }

    // Electric circuit: series or parallel
    final v = values.isNotEmpty ? values[0].round() : 12;
    final r1 = values.length > 1 ? values[1].round() : 4;
    final r2 = values.length > 2 ? values[2].round() : 6;
    final hasR3 = values.length > 3 && values[3] > 0;
    final r3 = hasR3 ? values[3].round() : 0;

    final left = 24.0, right = size.width - 24.0;
    final top = 34.0, bottom = size.height - 26.0;

    // Battery on bottom edge
    final midX = (left + right) / 2;
    canvas.drawLine(Offset(left, bottom), Offset(midX - 18, bottom), wire);
    canvas.drawLine(Offset(midX + 18, bottom), Offset(right, bottom), wire);
    canvas.drawLine(Offset(midX - 10, bottom - 13), Offset(midX - 10, bottom + 13), Paint()..color = accent..strokeWidth = 3.0);
    canvas.drawLine(Offset(midX + 10, bottom - 7), Offset(midX + 10, bottom + 7), Paint()..color = Colors.white..strokeWidth = 4.2);
    _paintText(canvas, '$v V', Offset(midX, bottom - 18), accent, size: 11.5);

    if (mode == 'series') {
      canvas.drawLine(Offset(left, top), Offset(left, bottom), wire);
      canvas.drawLine(Offset(right, top), Offset(right, bottom), wire);
      if (hasR3) {
        final x1 = left + (right - left) / 3;
        final x2 = left + 2 * (right - left) / 3;
        _drawResistor(canvas, Offset(left, top), Offset(x1, top), '$r1 Ω', accent);
        _drawResistor(canvas, Offset(x1, top), Offset(x2, top), '$r2 Ω', const Color(0xFF4CE0D2));
        _drawResistor(canvas, Offset(x2, top), Offset(right, top), '$r3 Ω', const Color(0xFFFF7BAC));
      } else {
        _drawResistor(canvas, Offset(left, top), Offset(midX, top), '$r1 Ω', accent);
        _drawResistor(canvas, Offset(midX, top), Offset(right, top), '$r2 Ω', const Color(0xFF4CE0D2));
      }
      _paintText(canvas, 'Seri Bağlı Devre', Offset(midX, (top + bottom) / 2 - 4), Colors.white70, size: 11);
    } else {
      final midY = (top + bottom) / 2 - 4;
      canvas.drawLine(Offset(left, top), Offset(left, bottom), wire);
      canvas.drawLine(Offset(right, top), Offset(right, bottom), wire);
      _drawResistor(canvas, Offset(left, top), Offset(right, top), 'R₁ = $r1 Ω', accent);
      _drawResistor(canvas, Offset(left, midY), Offset(right, midY), 'R₂ = $r2 Ω', const Color(0xFF4CE0D2));
      _paintText(canvas, 'Paralel Bağlı Devre', Offset(midX, bottom - 36), Colors.white70, size: 10.5);
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitVisualPainter old) =>
      old.mode != mode || old.labels != labels || old.values != values;
}

class _VennVisualPainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  final String highlight;
  final Color accent;

  _VennVisualPainter({
    required this.labels,
    required this.values,
    required this.highlight,
    required this.accent,
  });

  void _text(Canvas c, String t, Offset center, Color col, {double size = 12}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: col)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(8, 8, size.width - 16, size.height - 16), const Radius.circular(14));
    canvas.drawRRect(box, Paint()..color = const Color(0xFF0A1342));
    canvas.drawRRect(box, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = Colors.white24);

    final r = min(size.height * 0.34, size.width * 0.25);
    final cy = size.height * 0.54;
    final cA = Offset(size.width * 0.38, cy);
    final cB = Offset(size.width * 0.62, cy);
    const colA = Color(0xFFF6C453);
    const colB = Color(0xFF4CE0D2);

    canvas.drawCircle(cA, r, Paint()..color = colA.withValues(alpha: highlight == 'onlyA' || highlight == 'union' ? 0.34 : 0.18));
    canvas.drawCircle(cB, r, Paint()..color = colB.withValues(alpha: highlight == 'onlyB' || highlight == 'union' ? 0.34 : 0.18));
    canvas.drawCircle(cA, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = colA);
    canvas.drawCircle(cB, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = colB);

    final nameA = labels.isNotEmpty ? labels[0] : 'A';
    final nameB = labels.length > 1 ? labels[1] : 'B';
    _text(canvas, nameA, Offset(cA.dx - r * 0.35, cy - r - 11), colA, size: 11.5);
    _text(canvas, nameB, Offset(cB.dx + r * 0.35, cy - r - 11), colB, size: 11.5);
    _text(canvas, 'E', Offset(22, 22), Colors.white70, size: 11);

    final onlyA = values.isNotEmpty ? values[0].round() : 0;
    final both = values.length > 1 ? values[1].round() : 0;
    final onlyB = values.length > 2 ? values[2].round() : 0;
    final outside = values.length > 3 ? values[3].round() : 0;

    _text(canvas, '$onlyA', Offset(cA.dx - r * 0.42, cy), Colors.white, size: 15);
    _text(canvas, '$both', Offset(size.width * 0.50, cy), highlight == 'both' ? const Color(0xFFFFE082) : Colors.white, size: 16);
    _text(canvas, '$onlyB', Offset(cB.dx + r * 0.42, cy), Colors.white, size: 15);
    _text(canvas, 'Dış: $outside', Offset(size.width - 42, size.height - 22), Colors.white70, size: 10.5);
  }

  @override
  bool shouldRepaint(covariant _VennVisualPainter old) =>
      old.values != values || old.labels != labels || old.highlight != highlight;
}

class _CompassVisualPainter extends CustomPainter {
  final double bearingDeg;
  final double turnDeg;
  final Color accent;

  _CompassVisualPainter({
    required this.bearingDeg,
    required this.turnDeg,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) * 0.44;

    canvas.drawCircle(
      center,
      r + 3,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFE082), Color(0xFFB77B14), Color(0xFFF6C453)],
        ).createShader(Rect.fromCircle(center: center, radius: r + 3)),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF13266B), Color(0xFF060C2B)],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // 8 compass directions
    const dirs = [
      (0, 'K'), (45, 'KD'), (90, 'D'), (135, 'GD'),
      (180, 'G'), (225, 'GB'), (270, 'B'), (315, 'KB'),
    ];
    for (var d = 0; d < 360; d += 15) {
      final rad = (d - 90) * pi / 180;
      final major = d % 45 == 0;
      canvas.drawLine(
        Offset(center.dx + cos(rad) * (r - (major ? 10 : 5)), center.dy + sin(rad) * (r - (major ? 10 : 5))),
        Offset(center.dx + cos(rad) * (r - 2), center.dy + sin(rad) * (r - 2)),
        Paint()..color = major ? accent : Colors.white24..strokeWidth = major ? 2.0 : 1.0,
      );
    }
    for (final d in dirs) {
      final rad = (d.$1 - 90) * pi / 180;
      final isCard = d.$1 % 90 == 0;
      final pos = Offset(center.dx + cos(rad) * (r - 21), center.dy + sin(rad) * (r - 21));
      final tp = TextPainter(
        text: TextSpan(
          text: d.$2,
          style: TextStyle(
            fontSize: isCard ? 12 : 9.5,
            fontWeight: FontWeight.w900,
            color: d.$1 == 0 ? const Color(0xFFFF7B89) : (isCard ? const Color(0xFFFFE082) : Colors.white70),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
    }

    // Turn arc if non-zero
    final startRad = (bearingDeg - 90) * pi / 180;
    if (turnDeg.abs() > 0.1) {
      final sweep = turnDeg * pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * 0.52),
        startRad,
        sweep,
        false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 3.0..color = const Color(0xFF4CE0D2),
      );
    }

    // Main bearing needle
    final tip = Offset(center.dx + cos(startRad) * r * 0.62, center.dy + sin(startRad) * r * 0.62);
    final tail = Offset(center.dx - cos(startRad) * r * 0.25, center.dy - sin(startRad) * r * 0.25);
    canvas.drawLine(tail, tip, Paint()..color = accent..strokeWidth = 3.4..strokeCap = StrokeCap.round);
    canvas.drawCircle(tip, 4.5, Paint()..color = const Color(0xFF4CE0D2));
    canvas.drawCircle(center, 5, Paint()..color = accent);
    canvas.drawCircle(center, 2.2, Paint()..color = const Color(0xFF060C2B));
  }

  @override
  bool shouldRepaint(covariant _CompassVisualPainter old) =>
      old.bearingDeg != bearingDeg || old.turnDeg != turnDeg;
}

class _ColorLabVisualPainter extends CustomPainter {
  final String mode; // mix, rgb, spectrum
  final List<String> labels;
  final List<double> values;
  final Color accent;

  _ColorLabVisualPainter({
    required this.mode,
    required this.labels,
    required this.values,
    required this.accent,
  });

  Color _parseHex(String hex) {
    final clean = hex.replaceAll('#', '').trim();
    final v = int.tryParse(clean, radix: 16);
    if (v == null) return accent;
    return Color(clean.length == 6 ? (0xFF000000 | v) : v);
  }

  void _text(Canvas c, String t, Offset center, Color col, {double size = 11.5}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: col)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == 'spectrum') {
      final nm = (values.isNotEmpty ? values.first : 550.0).clamp(380.0, 750.0);
      final barRect = Rect.fromLTWH(16, size.height * 0.44, size.width - 32, 32);
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(10)),
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0xFF6B2CF5),
              Color(0xFF2E6BFF),
              Color(0xFF00D4FF),
              Color(0xFF2EE66B),
              Color(0xFFFFE033),
              Color(0xFFFF881A),
              Color(0xFFE62229),
            ],
          ).createShader(barRect),
      );
      final frac = (nm - 380.0) / 370.0;
      final mx = barRect.left + barRect.width * frac;
      canvas.drawLine(Offset(mx, barRect.top - 18), Offset(mx, barRect.bottom + 14), Paint()..color = Colors.white..strokeWidth = 2.6);
      canvas.drawCircle(Offset(mx, barRect.top - 22), 5, Paint()..color = accent);
      _text(canvas, 'λ = ${nm.round()} nm', Offset(mx.clamp(56, size.width - 56), barRect.top - 34), accent, size: 12);
      _text(canvas, '380 nm', Offset(barRect.left + 20, barRect.bottom + 20), Colors.white70, size: 10);
      _text(canvas, '565 nm', Offset(barRect.center.dx, barRect.bottom + 20), Colors.white70, size: 10);
      _text(canvas, '750 nm', Offset(barRect.right - 20, barRect.bottom + 20), Colors.white70, size: 10);
      return;
    }

    if (mode == 'rgb') {
      final hex = labels.isNotEmpty ? labels[0] : '#FF8800';
      final col = _parseHex(hex);
      final swatch = RRect.fromRectAndRadius(Rect.fromLTWH(18, 22, 92, size.height - 44), const Radius.circular(16));
      canvas.drawRRect(swatch, Paint()..color = col);
      canvas.drawRRect(swatch, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0..color = Colors.white70);

      final r = (col.r * 255).round();
      final g = (col.g * 255).round();
      final b = (col.b * 255).round();
      final bars = [('R', r, const Color(0xFFFF5A6E)), ('G', g, const Color(0xFF4BE085)), ('B', b, const Color(0xFF5AB2FF))];
      final bx = 128.0;
      final bw = max(60.0, size.width - bx - 18);
      for (var i = 0; i < 3; i++) {
        final y = 30.0 + i * 36.0;
        _text(canvas, '${bars[i].$1}: ${bars[i].$2}', Offset(bx + 26, y), Colors.white, size: 11);
        final track = RRect.fromRectAndRadius(Rect.fromLTWH(bx + 54, y - 6, max(20, bw - 54), 12), const Radius.circular(99));
        canvas.drawRRect(track, Paint()..color = Colors.white12);
        final fillW = max(6.0, (bw - 54) * (bars[i].$2 / 255.0));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx + 54, y - 6, fillW, 12), const Radius.circular(99)), Paint()..color = bars[i].$3);
      }
      return;
    }

    // Color mixing mode: Swatch A + Swatch B = ?
    final colA = labels.isNotEmpty ? _parseHex(labels[0]) : const Color(0xFFFF0000);
    final nameA = labels.length > 1 ? labels[1] : 'A';
    final colB = labels.length > 2 ? _parseHex(labels[2]) : const Color(0xFF00FF00);
    final nameB = labels.length > 3 ? labels[3] : 'B';

    final cy = size.height * 0.45;
    final r = min(size.height * 0.28, size.width * 0.13);
    final pA = Offset(size.width * 0.19, cy);
    final pB = Offset(size.width * 0.50, cy);
    final pQ = Offset(size.width * 0.81, cy);

    canvas.drawCircle(pA, r, Paint()..color = colA);
    canvas.drawCircle(pA, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0..color = Colors.white70);
    _text(canvas, nameA, Offset(pA.dx, cy + r + 15), Colors.white, size: 11);

    _text(canvas, '+', Offset((pA.dx + pB.dx) / 2, cy), accent, size: 22);

    canvas.drawCircle(pB, r, Paint()..color = colB);
    canvas.drawCircle(pB, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0..color = Colors.white70);
    _text(canvas, nameB, Offset(pB.dx, cy + r + 15), Colors.white, size: 11);

    _text(canvas, '=', Offset((pB.dx + pQ.dx) / 2, cy), accent, size: 22);

    canvas.drawCircle(pQ, r, Paint()..color = accent.withValues(alpha: 0.22));
    canvas.drawCircle(pQ, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = accent);
    _text(canvas, '?', pQ, accent, size: 22);
    _text(canvas, 'Sonuç', Offset(pQ.dx, cy + r + 15), accent, size: 11);
  }

  @override
  bool shouldRepaint(covariant _ColorLabVisualPainter old) =>
      old.mode != mode || old.labels != labels || old.values != values;
}

class _PianoVisualPainter extends CustomPainter {
  final List<String> highlightedKeys;
  final Color accent;

  _PianoVisualPainter({required this.highlightedKeys, required this.accent});

  static const _whiteKeys = ['C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5', 'D5', 'E5', 'F5', 'G5', 'A5', 'B5'];
  static const _blackOffsets = [
    (0, 'C#4'), (1, 'D#4'), (3, 'F#4'), (4, 'G#4'), (5, 'A#4'),
    (7, 'C#5'), (8, 'D#5'), (10, 'F#5'), (11, 'G#5'), (12, 'A#5'),
  ];

  String _norm(String raw) {
    final u = raw.trim().toUpperCase();
    return switch (u) {
      'DB4' => 'C#4',
      'EB4' => 'D#4',
      'GB4' => 'F#4',
      'AB4' => 'G#4',
      'BB4' => 'A#4',
      'DB5' => 'C#5',
      'EB5' => 'D#5',
      'GB5' => 'F#5',
      'AB5' => 'G#5',
      'BB5' => 'A#5',
      _ => u,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final active = highlightedKeys.map(_norm).toSet();
    final root = highlightedKeys.isNotEmpty ? _norm(highlightedKeys.first) : '';
    final kw = (size.width - 12) / _whiteKeys.length;
    final kh = size.height - 10;

    // White keys
    for (var i = 0; i < _whiteKeys.length; i++) {
      final k = _whiteKeys[i];
      final rect = Rect.fromLTWH(6 + i * kw, 5, kw - 1.2, kh);
      final isHit = active.contains(k);
      final isRoot = k == root && active.length > 1;
      final fill = isHit
          ? (isRoot ? const Color(0xFF4CE0D2) : accent)
          : const Color(0xFFF4F6FC);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, bottomLeft: const Radius.circular(5), bottomRight: const Radius.circular(5)),
        Paint()..color = fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, bottomLeft: const Radius.circular(5), bottomRight: const Radius.circular(5)),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0..color = const Color(0xFF141B40),
      );
      if (k == 'C4' || k == 'C5') {
        final tp = TextPainter(
          text: TextSpan(
            text: k,
            style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: isHit ? const Color(0xFF061028) : Colors.black54),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.bottom - 14));
      }
    }

    // Black keys
    final bw = kw * 0.64;
    final bh = kh * 0.60;
    for (final b in _blackOffsets) {
      final x = 6 + (b.$1 + 1) * kw - bw / 2 - 0.5;
      final rect = Rect.fromLTWH(x, 5, bw, bh);
      final isHit = active.contains(b.$2);
      final isRoot = b.$2 == root && active.length > 1;
      final fill = isHit
          ? (isRoot ? const Color(0xFF4CE0D2) : accent)
          : const Color(0xFF0A102B);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, bottomLeft: const Radius.circular(4), bottomRight: const Radius.circular(4)),
        Paint()..color = fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, bottomLeft: const Radius.circular(4), bottomRight: const Radius.circular(4)),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0..color = isHit ? Colors.white : Colors.white24,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PianoVisualPainter old) => old.highlightedKeys != highlightedKeys;
}

class QuestionActivityWidget extends StatefulWidget {
  final Question question;
  final Color accent;
  final bool revealed;
  final void Function(double rate, {String? languageOverride}) onPlayListeningAudio;
  final VoidCallback onStartPronunciationMic;
  final void Function(List<int> sequence) onSubmitSequence;
  final void Function(int optionIndex) onSelectChoice;
  final void Function(int estimate)? onSubmitSlider;
  final void Function(String word)? onSubmitAnagram;

  const QuestionActivityWidget({
    super.key,
    required this.question,
    required this.accent,
    required this.revealed,
    required this.onPlayListeningAudio,
    required this.onStartPronunciationMic,
    required this.onSubmitSequence,
    required this.onSelectChoice,
    this.onSubmitSlider,
    this.onSubmitAnagram,
  });

  @override
  State<QuestionActivityWidget> createState() => _QuestionActivityWidgetState();
}

class _QuestionActivityWidgetState extends State<QuestionActivityWidget> {
  final List<int> _orderedPick = [];
  int? _activeLeftIndex;
  final Map<int, int> _leftToRight = {};
  bool _showTranscript = false;
  int _playCount = 0;
  String? _selectedAccentOverride;

  // Slider state
  double _sliderValue = 0;
  bool _sliderInitialized = false;

  // Anagram state
  final List<int> _anagramPickedIndices = [];
  List<String> _anagramTileOrder = const [];
  bool _anagramHintShown = false;

  void _initInteractiveState() {
    _orderedPick.clear();
    _activeLeftIndex = null;
    _leftToRight.clear();
    _showTranscript = false;
    _playCount = 0;
    _selectedAccentOverride = null;
    _anagramPickedIndices.clear();
    _anagramHintShown = false;

    final act = widget.question.activity;
    if (act?.kind == ActivityKind.slider) {
      final minV = act!.sliderMin;
      final maxV = act.sliderMax;
      final step = max(1.0, act.sliderStep);
      final mid = ((minV + maxV) / 2 / step).round() * step;
      _sliderValue = mid.clamp(minV, maxV);
      _sliderInitialized = true;
    } else {
      _sliderInitialized = false;
    }
    if (act?.kind == ActivityKind.anagram) {
      _anagramTileOrder = List<String>.from(act!.items);
    } else {
      _anagramTileOrder = const [];
    }
  }

  @override
  void initState() {
    super.initState();
    _initInteractiveState();
  }

  @override
  void didUpdateWidget(covariant QuestionActivityWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _initInteractiveState();
    }
  }

  String _accentLabel(String? lang) {
    final l = (_selectedAccentOverride ?? lang ?? 'en-US').toLowerCase();
    if (l.startsWith('en-gb')) return 'İngiliz İngilizcesi (UK)';
    if (l.startsWith('en-au')) return 'Avustralya İngilizcesi (AU)';
    if (l.startsWith('en')) return 'Amerikan İngilizcesi (US)';
    if (l.startsWith('tr')) return 'Türkçe Seslendirme';
    return lang ?? 'Sesli Stüdyo';
  }

  void _triggerAudio(double rate) {
    setState(() => _playCount++);
    widget.onPlayListeningAudio(rate, languageOverride: _selectedAccentOverride);
  }

  Widget _buildAccentSwitcher(String? defaultLang) {
    final isEn = (defaultLang ?? '').toLowerCase().startsWith('en');
    if (!isEn) return const SizedBox.shrink();
    final active = (_selectedAccentOverride ?? defaultLang ?? 'en-US').toLowerCase();
    Widget chip(String code, String tag) {
      final selected = active.startsWith(tag.toLowerCase());
      return InkWell(
        onTap: () => setState(() => _selectedAccentOverride = tag),
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? widget.accent.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? widget.accent : Colors.white24,
            ),
          ),
          child: Text(
            code,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: selected ? widget.accent : Colors.white70,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(
            'Aksan:',
            style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.65), fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          chip('US', 'en-US'),
          const SizedBox(width: 5),
          chip('UK', 'en-GB'),
          const SizedBox(width: 5),
          chip('AU', 'en-AU'),
        ],
      ),
    );
  }

  Widget _buildAudioStudioPanel(QuestionActivity act, {required bool isDictation}) {
    final showText = _showTranscript || widget.revealed;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF15246B).withValues(alpha: 0.92),
            const Color(0xFF091036).withValues(alpha: 0.96),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.accent.withValues(alpha: 0.55), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDictation ? Icons.hearing_rounded : Icons.headphones_rounded,
                  color: widget.accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      act.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: widget.accent,
                      ),
                    ),
                    Text(
                      _accentLabel(act.language),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              if (_playCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CE0D2).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${_playCount}x',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF4CE0D2),
                    ),
                  ),
                ),
            ],
          ),
          _buildAccentSwitcher(act.language),
          const SizedBox(height: 10),
          // Stylized studio waveform bar
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < 22; i++)
                  Container(
                    width: 3,
                    height: 6.0 + ((i * 7 + _playCount * 3) % 15),
                    decoration: BoxDecoration(
                      color: i.isEven
                          ? widget.accent.withValues(alpha: 0.85)
                          : const Color(0xFF4CE0D2).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: () => _triggerAudio(0.95),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: const Color(0xFF061028),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text(
                    'Dinle (1.0x)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: () => _triggerAudio(0.72),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7CEEFF),
                  side: BorderSide(color: const Color(0xFF7CEEFF).withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                child: const Text('Yavaş', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: () => _triggerAudio(1.18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFB076),
                  side: BorderSide(color: const Color(0xFFFFB076).withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                ),
                child: const Text('1.2x', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
              ),
            ],
          ),
          if (act.transcript != null && act.transcript!.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (showText)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '“${act.transcript!}”',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              )
            else
              InkWell(
                onTap: () => setState(() => _showTranscript = true),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.subtitles_rounded, size: 14, color: Colors.white.withValues(alpha: 0.68)),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          isDictation
                              ? 'Sessiz ortamdaysan ipucu metnini göster'
                              : 'Sessiz ortamdaysan İngilizce altyazıyı göster',
                          style: TextStyle(
                            fontSize: 11.5,
                            decoration: TextDecoration.underline,
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSliderPanel(QuestionActivity act) {
    final minV = act.sliderMin;
    final maxV = max(minV + 1, act.sliderMax);
    final step = max(1.0, act.sliderStep);
    final divisions = max(1, ((maxV - minV) / step).round());
    final current = (_sliderInitialized ? _sliderValue : ((minV + maxV) / 2)).clamp(minV, maxV);
    final unitSuffix = act.sliderUnit.isNotEmpty ? ' ${act.sliderUnit}' : '';
    final target = act.sliderTarget;
    final diff = (current.round() - target).abs();
    final tol = act.sliderTolerance.round();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF15246B).withValues(alpha: 0.92),
            const Color(0xFF091036).withValues(alpha: 0.96),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.accent.withValues(alpha: 0.55), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: widget.accent, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  act.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: widget.accent),
                ),
              ),
              if (tol > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CE0D2).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '±$tol$unitSuffix',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF7CEEFF)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.accent.withValues(alpha: 0.65), width: 1.4),
              ),
              child: Text(
                '${current.round()}$unitSuffix',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: widget.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: widget.accent,
              inactiveTrackColor: Colors.white24,
              thumbColor: const Color(0xFFFFE082),
              overlayColor: widget.accent.withValues(alpha: 0.25),
              trackHeight: 5,
            ),
            child: Slider(
              min: minV,
              max: maxV,
              divisions: divisions,
              value: current,
              onChanged: widget.revealed
                  ? null
                  : (v) => setState(() {
                        _sliderValue = v;
                        _sliderInitialized = true;
                      }),
            ),
          ),
          Row(
            children: [
              Text(
                '${minV.round()}$unitSuffix',
                style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${maxV.round()}$unitSuffix',
                style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (widget.revealed) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (diff <= tol ? const Color(0xFF4BE085) : const Color(0xFFFF7B89)).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: diff <= tol ? const Color(0xFF4BE085) : const Color(0xFFFF7B89),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tam Değer: $target$unitSuffix',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                  Text(
                    diff == 0 ? 'Tam İsabet!' : 'Fark: $diff$unitSuffix',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: diff <= tol ? const Color(0xFF4BE085) : const Color(0xFFFF7B89),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => widget.onSubmitSlider?.call(current.round()),
              style: FilledButton.styleFrom(
                backgroundColor: widget.accent,
                foregroundColor: const Color(0xFF061028),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              icon: const Icon(Icons.lock_rounded, size: 17),
              label: const Text('Tahminimi Kilitle', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnagramPanel(QuestionActivity act) {
    final tiles = _anagramTileOrder.isNotEmpty ? _anagramTileOrder : act.items;
    final builtWord = [for (final idx in _anagramPickedIndices) if (idx < tiles.length) tiles[idx]].join();
    final target = act.anagramTarget;
    final hasAudio = act.transcript != null && act.transcript!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF15246B).withValues(alpha: 0.92),
            const Color(0xFF091036).withValues(alpha: 0.96),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.accent.withValues(alpha: 0.55), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.spellcheck_rounded, color: widget.accent, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  act.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: widget.accent),
                ),
              ),
              if (!widget.revealed && _anagramPickedIndices.isNotEmpty)
                InkWell(
                  onTap: () => setState(_anagramPickedIndices.clear),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('Temizle', style: TextStyle(fontSize: 11.5, color: Colors.white70)),
                  ),
                ),
            ],
          ),
          if (hasAudio) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _triggerAudio(0.92),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CE0D2),
                      foregroundColor: const Color(0xFF061028),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    ),
                    icon: const Icon(Icons.volume_up_rounded, size: 17),
                    label: const Text('Kelimeyi Dinle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _triggerAudio(0.70),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7CEEFF),
                    side: BorderSide(color: const Color(0xFF7CEEFF).withValues(alpha: 0.55)),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  ),
                  child: const Text('Yavaş', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Built answer slots
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var s = 0; s < tiles.length; s++)
                InkWell(
                  onTap: widget.revealed || s >= _anagramPickedIndices.length
                      ? null
                      : () => setState(() => _anagramPickedIndices.removeAt(s)),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 34,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s < _anagramPickedIndices.length
                          ? widget.accent.withValues(alpha: 0.26)
                          : Colors.black.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: s < _anagramPickedIndices.length ? widget.accent : Colors.white24,
                        width: 1.4,
                      ),
                    ),
                    child: Text(
                      s < _anagramPickedIndices.length
                          ? tiles[_anagramPickedIndices[s]]
                          : (_anagramHintShown && s == 0 && target.isNotEmpty ? target[0].toUpperCase() : ''),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: s < _anagramPickedIndices.length ? Colors.white : const Color(0xFF7CEEFF),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Scrambled interactive letter tiles
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 7,
            runSpacing: 7,
            children: [
              for (var i = 0; i < tiles.length; i++)
                Builder(
                  builder: (_) {
                    final used = _anagramPickedIndices.contains(i);
                    return InkWell(
                      onTap: widget.revealed || used
                          ? null
                          : () => setState(() => _anagramPickedIndices.add(i)),
                      borderRadius: BorderRadius.circular(11),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 38,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: used
                              ? null
                              : const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0xFF233899), Color(0xFF0E1A54)],
                                ),
                          color: used ? Colors.white.withValues(alpha: 0.05) : null,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: used ? Colors.white12 : widget.accent.withValues(alpha: 0.72),
                            width: 1.4,
                          ),
                        ),
                        child: Text(
                          tiles[i],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: used ? Colors.white24 : Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          if (!widget.revealed) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _anagramHintShown = true),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF7CEEFF),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 15),
                  label: const Text('İlk Harf', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _anagramPickedIndices.isEmpty
                      ? null
                      : () => setState(() => _anagramPickedIndices.removeLast()),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.backspace_outlined, size: 15),
                  label: const Text('Geri Al', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _anagramPickedIndices.length == tiles.length
                  ? () => widget.onSubmitAnagram?.call(builtWord)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: widget.accent,
                foregroundColor: const Color(0xFF061028),
              ),
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                _anagramPickedIndices.length == tiles.length
                    ? 'Kelimeyi Onayla ($builtWord)'
                    : '${_anagramPickedIndices.length}/${tiles.length} harf dizildi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final act = widget.question.activity;
    if (act == null) return const SizedBox.shrink();

    switch (act.kind) {
      case ActivityKind.listening:
        return _buildAudioStudioPanel(act, isDictation: false);

      case ActivityKind.dictation:
        return _buildAudioStudioPanel(act, isDictation: true);

      case ActivityKind.slider:
        return _buildSliderPanel(act);

      case ActivityKind.anagram:
        return _buildAnagramPanel(act);

      case ActivityKind.ordering:
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.accent.withValues(alpha: 0.35)),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                  for (var i = 0; i < act.items.length; i++) _buildOrderChip(i, act.items[i], act.solution),
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
            border: Border.all(color: widget.accent.withValues(alpha: 0.35)),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                          _buildMatchLeftTile(i, act.left[i], act.solution),
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF15246B).withValues(alpha: 0.92),
                const Color(0xFF091036).withValues(alpha: 0.96),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.accent.withValues(alpha: 0.55), width: 1.3),
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
                      '${act.title} · ${_accentLabel(act.language)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: widget.accent,
                      ),
                    ),
                  ),
                ],
              ),
              _buildAccentSwitcher(act.language),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.accent.withValues(alpha: 0.30)),
                ),
                child: Column(
                  children: [
                    Text(
                      '“$phrase”',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    if (act.items.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        act.items.first,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7CEEFF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _triggerAudio(0.95),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: widget.accent.withValues(alpha: 0.65)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      icon: const Icon(Icons.volume_up_rounded, size: 17),
                      label: const Text('Dinle', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () => _triggerAudio(0.70),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF7CEEFF),
                      side: BorderSide(color: const Color(0xFF7CEEFF).withValues(alpha: 0.55)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    child: const Text('0.7x', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.revealed ? null : widget.onStartPronunciationMic,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.accent,
                        foregroundColor: const Color(0xFF06101F),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      icon: const Icon(Icons.mic_rounded, size: 17),
                      label: const Text('Söyle', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Mikrofonla yüksek sesle okuyabilir veya sessiz ortamdaysan aşağıdaki şıktan çözebilirsin.',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildOrderChip(int index, String label, List<int> solution) {
    final pos = _orderedPick.indexOf(index);
    final selected = pos >= 0;
    final correctPos = solution.indexOf(index);
    final isRightSpot = widget.revealed && selected && pos == correctPos;
    final isWrongSpot = widget.revealed && selected && pos != correctPos;

    Color borderCol = selected ? widget.accent : Colors.white.withValues(alpha: 0.16);
    Color bgCol = selected ? widget.accent.withValues(alpha: 0.24) : Colors.white.withValues(alpha: 0.07);
    if (isRightSpot) {
      borderCol = const Color(0xFF4BE085);
      bgCol = const Color(0xFF4BE085).withValues(alpha: 0.20);
    } else if (isWrongSpot) {
      borderCol = const Color(0xFFFF7B89);
      bgCol = const Color(0xFFFF7B89).withValues(alpha: 0.20);
    }

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
          color: bgCol,
          border: Border.all(color: borderCol),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              CircleAvatar(
                radius: 10,
                backgroundColor: isRightSpot
                    ? const Color(0xFF4BE085)
                    : (isWrongSpot ? const Color(0xFFFF7B89) : widget.accent),
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
                widget.revealed && correctPos >= 0 ? '$label (#${correctPos + 1})' : label,
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

  Widget _buildMatchLeftTile(int i, String text, List<int> solution) {
    final isActive = _activeLeftIndex == i;
    final matchedRight = _leftToRight[i];
    final c = _pairColors[i % _pairColors.length];
    final revealedOk = widget.revealed && i < solution.length && matchedRight == solution[i];
    final revealedWrong = widget.revealed && matchedRight != null && !revealedOk;

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
            color: revealedOk
                ? const Color(0xFF4BE085).withValues(alpha: 0.22)
                : revealedWrong
                    ? const Color(0xFFFF7B89).withValues(alpha: 0.22)
                    : (isActive || matchedRight != null
                        ? c.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.06)),
            border: Border.all(
              color: revealedOk
                  ? const Color(0xFF4BE085)
                  : revealedWrong
                      ? const Color(0xFFFF7B89)
                      : (isActive || matchedRight != null ? c : Colors.white.withValues(alpha: 0.15)),
              width: isActive ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${i + 1}. $text',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (revealedOk)
                const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF4BE085))
              else if (revealedWrong)
                const Icon(Icons.cancel_rounded, size: 15, color: Color(0xFFFF7B89)),
            ],
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
