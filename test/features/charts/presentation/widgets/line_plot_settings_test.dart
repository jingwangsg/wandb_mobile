import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/features/charts/models/metric_chart_rule.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/line_plot_settings.dart';

void main() {
  testWidgets('axis bounds are typed as numbers, cleared back to auto, and '
      'reset with the rule', (tester) async {
    MetricChartRule? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinePlotSettings(
            rule: const MetricChartRule(useAutoXMax: false, xMax: 1000),
            resetRule: const MetricChartRule(useAutoMin: false, min: -1),
            scope: 'Applies to this line plot',
            xAxisOptions: const [],
            onChanged: (rule) => saved = rule,
            onReset: () {},
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'X max'))
          .controller
          ?.text,
      '1000',
    );

    await tester.enterText(find.widgetWithText(TextField, 'Y max'), '0.5');
    expect(saved?.resolvedMax, 0.5);
    expect(saved?.resolvedXMax, 1000, reason: 'other bounds are kept');

    await tester.enterText(find.widgetWithText(TextField, 'X min'), '-');
    expect(saved?.useAutoXMin, true, reason: 'an unfinished entry is auto');
    await tester.enterText(find.widgetWithText(TextField, 'X min'), '-2');
    expect(saved?.resolvedXMin, -2);
    await tester.enterText(find.widgetWithText(TextField, 'X min'), '1e999');
    expect(saved?.useAutoXMin, true, reason: 'infinity cannot be saved');

    await tester.enterText(find.widgetWithText(TextField, 'Y max'), '');
    expect(saved?.useAutoMax, true);

    await tester.tap(find.text('Reset this line plot'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Y min'))
          .controller
          ?.text,
      '-1',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'X max'))
          .controller
          ?.text,
      '',
    );
    expect(tester.takeException(), isNull);
  });
}
