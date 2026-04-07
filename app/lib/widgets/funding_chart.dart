import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A lightweight funding rate line chart using CustomPaint.
/// Draws multiple series (one per exchange) with a zero line.
class FundingChart extends StatelessWidget {
  final Map<String, List<FundingPoint>> series; // source → data points
  final double height;

  const FundingChart({super.key, required this.series, this.height = 180});

  static const _colors = [
    Color(0xFF007AFF), // blue
    Color(0xFFFF9500), // orange
    Color(0xFF34C759), // green
    Color(0xFFFF3B30), // red
    Color(0xFFAF52DE), // purple
    Color(0xFF5AC8FA), // light blue
    Color(0xFFFF2D55), // pink
    Color(0xFF8E8E93), // gray
  ];

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return SizedBox(height: height,
          child: const Center(child: Text('无数据', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13))));
    }
    return Column(children: [
      SizedBox(height: height,
          child: CustomPaint(size: Size(double.infinity, height),
              painter: _ChartPainter(series: series, colors: _colors))),
      const SizedBox(height: 8),
      // Legend
      Wrap(spacing: 16, runSpacing: 4, children:
          series.keys.toList().asMap().entries.map((e) => Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 3, decoration: BoxDecoration(
                color: _colors[e.key % _colors.length], borderRadius: BorderRadius.circular(1))),
            const SizedBox(width: 4),
            Text(e.value, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
          ])).toList()),
    ]);
  }
}

class FundingPoint {
  final DateTime time;
  final double rate8h; // normalized to 8h rate
  const FundingPoint({required this.time, required this.rate8h});
}

class _ChartPainter extends CustomPainter {
  final Map<String, List<FundingPoint>> series;
  final List<Color> colors;
  _ChartPainter({required this.series, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    const padL = 48.0, padR = 8.0, padT = 8.0, padB = 20.0;
    final chartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;

    // Find time and rate bounds across all series
    double minRate = 0, maxRate = 0;
    int minTime = DateTime.now().millisecondsSinceEpoch;
    int maxTime = 0;

    for (final pts in series.values) {
      for (final p in pts) {
        if (p.rate8h < minRate) minRate = p.rate8h;
        if (p.rate8h > maxRate) maxRate = p.rate8h;
        final t = p.time.millisecondsSinceEpoch;
        if (t < minTime) minTime = t;
        if (t > maxTime) maxTime = t;
      }
    }

    // Add padding to rate range
    final rateRange = max(maxRate - minRate, 0.0001);
    minRate -= rateRange * 0.1;
    maxRate += rateRange * 0.1;
    final timeRange = max(maxTime - minTime, 1);

    double toX(int t) => padL + (t - minTime) / timeRange * chartW;
    double toY(double r) => padT + (1 - (r - minRate) / (maxRate - minRate)) * chartH;

    // Zero line
    final zeroY = toY(0);
    if (zeroY >= padT && zeroY <= padT + chartH) {
      canvas.drawLine(
        Offset(padL, zeroY), Offset(padL + chartW, zeroY),
        Paint()..color = const Color(0xFFE5E5EA)..strokeWidth = 0.5,
      );
      // "0%" label
      final tp = TextPainter(text: const TextSpan(text: '0%',
          style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
          textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(padL - tp.width - 6, zeroY - tp.height / 2));
    }

    // Y-axis labels (top and bottom)
    void drawYLabel(double rate, double y) {
      final pct = (rate * 100).toStringAsFixed(3);
      final tp = TextPainter(text: TextSpan(text: '$pct%',
          style: const TextStyle(fontSize: 9, color: Color(0xFFAEAEB2))),
          textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(padL - tp.width - 4, y - tp.height / 2));
    }
    drawYLabel(maxRate, padT + 4);
    drawYLabel(minRate, padT + chartH - 4);

    // Draw series
    int ci = 0;
    for (final entry in series.entries) {
      final pts = entry.value;
      if (pts.length < 2) { ci++; continue; }

      final sorted = List.of(pts)..sort((a, b) => a.time.compareTo(b.time));
      final path = Path();
      for (int i = 0; i < sorted.length; i++) {
        final x = toX(sorted[i].time.millisecondsSinceEpoch);
        final y = toY(sorted[i].rate8h);
        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }

      canvas.drawPath(path, Paint()
        ..color = colors[ci % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..isAntiAlias = true);

      ci++;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series.length != series.length;
}
