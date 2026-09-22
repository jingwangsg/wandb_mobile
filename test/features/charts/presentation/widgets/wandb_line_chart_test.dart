import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/wandb_line_chart.dart';

void main() {
  const series = [
    MetricSeries(
      key: 'loss',
      points: [
        MetricPoint(step: 0, value: 1.2, low: 1.1, high: 1.3),
        MetricPoint(step: 1, value: 0.4, low: 0.35, high: 0.5),
      ],
    ),
  ];

  testWidgets(
    'an automatic Y range fits the data instead of starting at zero',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WandbLineChart(series: series, yAxisMax: 1.2)),
        ),
      );
      await tester.pumpAndSettle();
      final chart = tester.widget<SfCartesianChart>(
        find.byType(SfCartesianChart),
      );
      final yAxis = chart.primaryYAxis as NumericAxis;
      expect(yAxis.rangePadding, ChartRangePadding.round);
      expect(yAxis.minimum, isNull);
      expect(yAxis.maximum, 1.2);
      expect(chart.series.whereType<RangeAreaSeries>(), hasLength(1));
      expect(chart.series.whereType<LineSeries>(), hasLength(1));
    },
  );

  testWidgets('smoothing keeps the original line behind the smoothed one and '
      'excluding outliers scales to the lines', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WandbLineChart(
            series: series,
            smoothing: 0.5,
            smoothingType: 'exponential',
            ignoreOutliers: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chart = tester.widget<SfCartesianChart>(
      find.byType(SfCartesianChart),
    );
    final lines = chart.series.whereType<LineSeries>().toList();
    expect(lines, hasLength(2), reason: 'original plus smoothed');
    expect(lines.first.isVisibleInLegend, false);
    expect(lines.last.name, 'loss');
    final yAxis = chart.primaryYAxis as NumericAxis;
    // Smoothed values run from 1.2 down towards 0.4; the band's 1.3 and 0.35
    // are outside the fitted range and clip.
    expect(yAxis.maximum, lessThan(1.3));
    expect(yAxis.minimum, greaterThan(0.35));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WandbLineChart(
            series: series,
            smoothing: 0.5,
            showOriginal: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SfCartesianChart>(find.byType(SfCartesianChart))
          .series
          .whereType<LineSeries>(),
      hasLength(1),
    );
  });

  testWidgets('legend position, line colour and dash reach the chart', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WandbLineChart(
            series: [
              MetricSeries(
                key: 'a',
                points: [
                  MetricPoint(step: 0, value: 1),
                  MetricPoint(step: 1, value: 2),
                ],
                color: 0xFFFF0000,
                dashArray: [6, 3],
              ),
            ],
            legendPosition: 'east',
            showLegend: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chart = tester.widget<SfCartesianChart>(
      find.byType(SfCartesianChart),
    );
    expect(chart.legend.position, LegendPosition.right);
    final line = chart.series.whereType<LineSeries>().single;
    expect(line.color, const Color(0xFFFF0000));
    expect(line.dashArray, [6, 3]);
  });
}
