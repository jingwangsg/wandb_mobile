import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../../../core/models/metric_point.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/downsampling.dart';
import '../../../../core/utils/format_utils.dart';

class WandbLineChart extends StatefulWidget {
  const WandbLineChart({
    super.key,
    required this.series,
    this.smoothing = 0,
    this.xAxis = '_step',
    this.title,
    this.yAxisMin,
    this.yAxisMax,
    this.xAxisMin,
    this.xAxisMax,
    this.showLegend = true,
    this.logScale = false,
  });

  final List<MetricSeries> series;
  final double smoothing;

  /// `_step`, `_absolute_runtime`, `_timestamp`, or a history key whose value
  /// is held in [MetricPoint.x].
  final String xAxis;
  final String? title;
  final double? yAxisMin;
  final double? yAxisMax;
  final double? xAxisMin;
  final double? xAxisMax;
  final bool showLegend;
  final bool logScale;

  @override
  State<WandbLineChart> createState() => _WandbLineChartState();
}

class _WandbLineChartState extends State<WandbLineChart> {
  final _zoom = ZoomPanBehavior(
    enablePinching: true,
    enablePanning: true,
    enableDoubleTapZooming: true,
    zoomMode: ZoomMode.xy,
    maximumZoomLevel: 0.01,
  );
  late TrackballBehavior _trackball;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = Theme.of(context).colorScheme;
    _trackball = TrackballBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
      lineType: TrackballLineType.vertical,
      lineColor: colors.onSurfaceVariant,
      tooltipSettings: InteractiveTooltip(
        color: colors.inverseSurface,
        textStyle: TextStyle(
          fontSize: 12,
          fontFamily: 'SourceSans3',
          color: colors.onInverseSurface,
        ),
      ),
      markerSettings: const TrackballMarkerSettings(
        markerVisibility: TrackballVisibilityMode.visible,
        height: 6,
        width: 6,
      ),
    );
  }

  @override
  void didUpdateWidget(WandbLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.xAxis != widget.xAxis ||
        oldWidget.logScale != widget.logScale) {
      _zoom.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.series.isEmpty || widget.series.every((s) => s.isEmpty)) {
      return const Center(child: Text('No data'));
    }
    if (widget.logScale &&
        !widget.series.any(
          (s) => s.points.any((p) => p.value.isFinite && p.value > 0),
        )) {
      return const Center(
        child: Text(
          'No positive values to plot on a log scale',
          textAlign: TextAlign.center,
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final processed =
            widget.series.map((series) {
              final origin =
                  series.points
                      .where((p) => p.timestamp != null)
                      .firstOrNull
                      ?.timestamp;
              var points = <MetricPoint>[];
              for (final point in series.points) {
                if (!point.value.isFinite) continue;
                final x = switch (widget.xAxis) {
                  '_step' => point.step.toDouble(),
                  '_absolute_runtime' =>
                    origin != null && point.timestamp != null
                        ? point.timestamp!.difference(origin).inMilliseconds /
                            1000
                        : point.step.toDouble(),
                  '_timestamp' =>
                    (point.timestamp?.millisecondsSinceEpoch ?? point.step)
                        .toDouble(),
                  _ => point.x,
                };
                if (x == null || !x.isFinite) continue;
                points.add(
                  MetricPoint(
                    step: x,
                    value: point.value,
                    timestamp: point.timestamp,
                  ),
                );
              }
              points = timeWeightedSmoothing(points, widget.smoothing);
              final target =
                  constraints.maxWidth.isFinite
                      ? constraints.maxWidth.round().clamp(120, 1200)
                      : 300;
              return MetricSeries(
                key: series.key,
                points: lttbDownsample(points, target),
              );
            }).toList();
        return SfCartesianChart(
          margin: const EdgeInsets.fromLTRB(4, 4, 8, 0),
          title: ChartTitle(
            text: widget.title ?? '',
            textStyle: TextStyle(
              color: colors.onSurface,
              fontFamily: 'SourceSans3',
            ),
          ),
          backgroundColor: Colors.transparent,
          plotAreaBorderWidth: 0,
          zoomPanBehavior: _zoom,
          trackballBehavior: _trackball,
          onTrackballPositionChanging: (args) {
            final point = args.chartPointInfo.chartPoint;
            if (point == null) return;
            args.chartPointInfo.header =
                widget.xAxis == '_timestamp'
                    ? DateTime.fromMillisecondsSinceEpoch(
                      (point.x as num).toInt(),
                    ).toLocal().toString()
                    : '${xAxisLabel(widget.xAxis)} ${formatMetricValue(point.x)}';
            final value = point.y;
            if (value == null) return;
            final label = value.toStringAsFixed(4);
            args.chartPointInfo.label =
                widget.series.length == 1
                    ? label
                    : '${args.chartPointInfo.seriesName}: $label';
          },
          legend: Legend(
            isVisible: widget.showLegend && processed.length > 1,
            position: LegendPosition.bottom,
            overflowMode: LegendItemOverflowMode.scroll,
            textStyle: TextStyle(
              fontFamily: 'SourceSans3',
              fontSize: 12,
              color: colors.onSurfaceVariant,
            ),
          ),
          primaryXAxis: NumericAxis(
            minimum: widget.xAxisMin,
            maximum: widget.xAxisMax,
            majorGridLines: const MajorGridLines(width: 0),
            majorTickLines: const MajorTickLines(size: 0),
            axisLine: AxisLine(color: colors.outlineVariant),
            labelStyle: TextStyle(
              fontFamily: 'SourceSans3',
              fontSize: 12,
              color: colors.onSurfaceVariant,
            ),
            enableAutoIntervalOnZooming: true,
          ),
          primaryYAxis:
              widget.logScale
                  ? LogarithmicAxis(
                    minimum:
                        widget.yAxisMin != null && widget.yAxisMin! > 0
                            ? widget.yAxisMin
                            : null,
                    maximum:
                        widget.yAxisMax != null && widget.yAxisMax! > 0
                            ? widget.yAxisMax
                            : null,
                    majorGridLines: MajorGridLines(
                      color: colors.outlineVariant,
                      width: 0.5,
                    ),
                    majorTickLines: const MajorTickLines(size: 0),
                    axisLine: const AxisLine(width: 0),
                    labelStyle: TextStyle(
                      fontFamily: 'SourceSans3',
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  )
                  : NumericAxis(
                    minimum: widget.yAxisMin,
                    maximum: widget.yAxisMax,
                    anchorRangeToVisiblePoints: true,
                    majorGridLines: MajorGridLines(
                      color: colors.outlineVariant,
                      width: 0.5,
                    ),
                    majorTickLines: const MajorTickLines(size: 0),
                    axisLine: const AxisLine(width: 0),
                    labelStyle: TextStyle(
                      fontFamily: 'SourceSans3',
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
          series:
              processed
                  .asMap()
                  .entries
                  .map(
                    (entry) => LineSeries<MetricPoint, num>(
                      dataSource: entry.value.points,
                      name: entry.value.key,
                      xValueMapper: (point, _) => point.step,
                      yValueMapper:
                          (point, _) =>
                              widget.logScale && point.value <= 0
                                  ? null
                                  : point.value,
                      emptyPointSettings: const EmptyPointSettings(
                        mode: EmptyPointMode.gap,
                      ),
                      color:
                          WandbColors.chartPalette[entry.key %
                              WandbColors.chartPalette.length],
                      width: 1.6,
                      animationDuration: 0,
                      markerSettings: MarkerSettings(
                        isVisible: entry.value.points.length == 1,
                        width: 5,
                        height: 5,
                      ),
                    ),
                  )
                  .toList(),
        );
      },
    );
  }
}

/// X axes W&B derives from every history row, in the web's menu order.
const builtInXAxes = ['_step', '_runtime', '_absolute_runtime', '_timestamp'];

/// Display name for a W&B X-axis key; history keys are shown verbatim.
String xAxisLabel(String xAxis) => switch (xAxis) {
  '_step' => 'Step',
  '_runtime' => 'Relative Time (Process)',
  '_absolute_runtime' => 'Relative Time (Wall)',
  '_timestamp' => 'Wall Time',
  _ => xAxis,
};
