import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../../../core/models/metric_point.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/downsampling.dart';

const _minimumTargetPoints = 120;
const _fallbackTargetPoints = 300;

/// Core Syncfusion line chart wrapper optimized for mobile interaction.
/// Supports native pan/zoom gestures, trackball tooltip, multi-metric overlay.
class WandbLineChart extends StatelessWidget {
  const WandbLineChart({
    super.key,
    required this.series,
    this.smoothing = 0,
    this.xAxisMode = XAxisMode.step,
    this.title,
  });

  final List<MetricSeries> series;
  final double smoothing;
  final XAxisMode xAxisMode;
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty || series.every((s) => s.isEmpty)) {
      return const Center(child: Text('No data'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 500;
        final fontSize = wide ? 12.0 : 10.0;
        final processedSeries = _processSeries(constraints.maxWidth);

        return SfCartesianChart(
          // Title
          title:
              title != null
                  ? ChartTitle(
                    text: title!,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  )
                  : const ChartTitle(text: ''),

          // Background
          plotAreaBackgroundColor: Colors.transparent,
          plotAreaBorderColor: Colors.white10,
          backgroundColor: Colors.transparent,

          // ─── Gesture handling (core mobile UX) ─────────────
          zoomPanBehavior: ZoomPanBehavior(
            enablePinching: true, // Two-finger zoom
            enablePanning: true, // One-finger pan (when zoomed)
            enableDoubleTapZooming: true, // Double-tap to zoom in
            zoomMode: ZoomMode.x, // X-axis zoom only (most useful)
            enableSelectionZooming: false, // No box-select on mobile
            maximumZoomLevel: 0.05, // Allow 20x zoom
          ),

          // ─── Trackball for data inspection (replaces web hover) ──
          trackballBehavior: TrackballBehavior(
            enable: true,
            activationMode: ActivationMode.singleTap,
            tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
            lineType: TrackballLineType.vertical,
            lineColor: Colors.white24,
            tooltipSettings: const InteractiveTooltip(
              color: Color(0xFF2A2A4A),
              borderColor: Colors.white24,
              borderWidth: 1,
              textStyle: TextStyle(fontSize: 11, fontFamily: 'JetBrains Mono'),
            ),
          ),

          // ─── Legend (bottom on narrow, right on wide) ─────
          legend: Legend(
            isVisible: processedSeries.length > 1,
            position: wide ? LegendPosition.right : LegendPosition.bottom,
            overflowMode: LegendItemOverflowMode.wrap,
            textStyle: TextStyle(fontSize: fontSize, color: Colors.white70),
          ),

          // ─── Axes ──────────────────────────────────────────
          primaryXAxis: NumericAxis(
            title: AxisTitle(
              text: xAxisMode.label,
              textStyle: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
            majorGridLines: const MajorGridLines(color: Colors.white10),
            axisLine: const AxisLine(color: Colors.white24),
            labelStyle: TextStyle(fontSize: fontSize, color: Colors.white38),
            enableAutoIntervalOnZooming: true,
          ),
          primaryYAxis: NumericAxis(
            majorGridLines: const MajorGridLines(color: Colors.white10),
            axisLine: const AxisLine(color: Colors.white24),
            labelStyle: TextStyle(fontSize: fontSize, color: Colors.white38),
            anchorRangeToVisiblePoints: true, // Rescale Y when zoomed on X
          ),

          // ─── Series ────────────────────────────────────────
          series:
              processedSeries.asMap().entries.map((entry) {
                final index = entry.key;
                final s = entry.value;
                final color =
                    WandbColors.chartPalette[index %
                        WandbColors.chartPalette.length];

                return LineSeries<MetricPoint, num>(
                  dataSource: s.points,
                  xValueMapper: (point, _) => _xValue(point),
                  yValueMapper: (point, _) => point.value,
                  name: s.key,
                  color: color,
                  width: 2,
                  animationDuration: 0, // No animation = snappier feel
                  enableTooltip: true,
                );
              }).toList(),
        );
      },
    );
  }

  List<MetricSeries> _processSeries(double availableWidth) {
    return series.map((entry) {
      var points = lttbDownsample(
        entry.points,
        _targetPointCount(availableWidth, entry.points.length),
      );
      if (smoothing > 0) {
        points = applySmoothing(points, smoothing);
      }
      return MetricSeries(key: entry.key, points: points);
    }).toList();
  }

  int _targetPointCount(double availableWidth, int sourceLength) {
    if (sourceLength <= _minimumTargetPoints) {
      return sourceLength;
    }

    final widthTarget =
        availableWidth.isFinite && availableWidth > 0
            ? availableWidth.round()
            : _fallbackTargetPoints;

    return widthTarget.clamp(_minimumTargetPoints, sourceLength).toInt();
  }

  num _xValue(MetricPoint point) {
    switch (xAxisMode) {
      case XAxisMode.step:
        return point.step;
      case XAxisMode.relativeTime:
        return point.timestamp?.millisecondsSinceEpoch ?? point.step;
      case XAxisMode.wallClock:
        return point.timestamp?.millisecondsSinceEpoch ?? point.step;
    }
  }
}

enum XAxisMode {
  step('Step'),
  relativeTime('Relative Time'),
  wallClock('Wall Clock');

  const XAxisMode(this.label);
  final String label;
}
