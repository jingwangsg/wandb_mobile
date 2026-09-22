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
}
