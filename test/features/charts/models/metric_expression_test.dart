import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/features/charts/models/metric_expression.dart';

void main() {
  double? constant(Map<String, double> values) => null;

  test(
    'arithmetic follows precedence, parentheses, powers and unary minus',
    () {
      double? eval(String source) =>
          MetricExpression.parse(source).evaluate((_, _) => null);
      expect(eval('1 + 2 * 3'), 7);
      expect(eval('(1 + 2) * 3'), 9);
      expect(eval('2 ^ 3 ^ 2'), 512, reason: 'right associative');
      expect(eval('-2 ^ 2'), 4, reason: 'unary binds tighter, as in the web');
      expect(eval('8 / 2 / 2'), 2);
      expect(eval('1e3 - 0.5'), 999.5);
      expect(eval('1 / 0'), isNull, reason: 'non-finite results are dropped');
      expect(constant(const {}), isNull);
    },
  );

  test('metric references read the current value or a run aggregate', () {
    final expression = MetricExpression.parse(
      r'${train/loss} - ${train/loss:min} + ${lr:max}',
    );
    expect(expression.keys, {'train/loss', 'lr'});
    final value = expression.evaluate(
      (key, aggregate) => switch ((key, aggregate)) {
        ('train/loss', null) => 0.9,
        ('train/loss', 'min') => 0.4,
        ('lr', 'max') => 0.01,
        _ => null,
      },
    );
    expect(value, closeTo(0.51, 1e-12));
    expect(expression.evaluate((_, _) => null), isNull);
  });

  test('malformed expressions are rejected with a message', () {
    for (final source in [
      '',
      '1 +',
      '(1',
      r'${}',
      r'${a:median}',
      'foo',
      '1 2',
    ]) {
      expect(
        () => MetricExpression.parse(source),
        throwsFormatException,
        reason: source,
      );
    }
  });

  test('expressionSeries joins metrics by axis position and skips gaps', () {
    final fetched = [
      const MetricSeries(
        key: 'a',
        points: [
          MetricPoint(step: 0, value: 1, x: 0),
          MetricPoint(step: 1, value: 2, x: 10),
          MetricPoint(step: 2, value: 3, x: 20),
        ],
      ),
      const MetricSeries(
        key: 'b',
        points: [
          MetricPoint(step: 0, value: 10, x: 0),
          MetricPoint(step: 2, value: 30, x: 20),
        ],
      ),
    ];
    final series = expressionSeries(
      MetricExpression.parse(r'${a} + ${b} - ${a:min}'),
      fetched,
    );
    expect(series.key, r'${a} + ${b} - ${a:min}');
    expect(series.points.map((p) => (p.x, p.value)), [
      (0.0, 10.0),
      (20.0, 32.0),
    ], reason: 'x = 10 has no value for b and is skipped');
    expect(
      expressionSeries(
        MetricExpression.parse(r'${missing} * 2'),
        fetched,
      ).points,
      isEmpty,
    );
  });
}
