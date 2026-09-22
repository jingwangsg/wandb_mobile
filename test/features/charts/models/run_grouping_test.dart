import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/features/charts/models/run_grouping.dart';

void main() {
  const run = WandbRun(
    id: 'id',
    name: 'run-1',
    displayName: 'Run 1',
    state: RunState.finished,
    group: 'sweep-a',
    config: {
      'lr': {'value': 0.001},
      'model': {
        'value': {'layers': 24, 'name': 'gpt'},
      },
    },
  );

  test(
    'grouping keys read wrapped config values, nested paths and run fields',
    () {
      expect(groupValue(run, 'config:lr'), '0.001');
      expect(groupValue(run, 'config:model.name'), 'gpt');
      expect(groupValue(run, 'config:model.layers'), '24');
      expect(groupValue(run, 'config:missing'), '-');
      expect(groupValue(run, 'run:group'), 'sweep-a');
      expect(groupValue(run, 'run:jobType'), '-');
      expect(groupValue(run, 'run:username'), '-');
      expect(groupValue(run, 'run:state'), 'finished');
      expect(
        groupLabel(run, ['config:lr', 'run:group']),
        'lr=0.001, group=sweep-a',
      );
    },
  );

  test(
    'aggregateLines resamples onto one grid and draws the spread as a band',
    () {
      final lines = [
        [
          const MetricPoint(step: 0, value: 0, x: 0),
          const MetricPoint(step: 1, value: 10, x: 10),
        ],
        [
          const MetricPoint(step: 0, value: 4, x: 0),
          const MetricPoint(step: 1, value: 6, x: 5),
          const MetricPoint(step: 2, value: 8, x: 10),
        ],
      ];
      final mean = aggregateLines('g', lines, 'mean', 'minmax', gridSize: 3);
      expect(mean.points.map((p) => p.x), [0, 5, 10]);
      expect(mean.points.map((p) => p.value), [2, 5.5, 9]);
      expect(
        mean.points[1].low,
        5,
        reason: 'first line interpolates to 5 at x=5',
      );
      expect(mean.points[1].high, 6);

      final max = aggregateLines('g', lines, 'max', 'none', gridSize: 3);
      expect(max.points.map((p) => p.value), [4, 6, 10]);
      expect(max.points.every((p) => p.low == null && p.high == null), true);

      final deviation = aggregateLines(
        'g',
        lines,
        'median',
        'stddev',
        gridSize: 3,
      );
      expect(deviation.points.first.value, 4, reason: 'upper median of [0, 4]');
      expect(deviation.points.first.low, closeTo(0, 1e-9));
      expect(deviation.points.first.high, closeTo(4, 1e-9));
    },
  );

  test('a lone line has no band and partial overlap only covers shared x', () {
    final lines = [
      [
        const MetricPoint(step: 0, value: 1, x: 0),
        const MetricPoint(step: 1, value: 1, x: 10),
      ],
      [
        const MetricPoint(step: 0, value: 3, x: 5),
        const MetricPoint(step: 1, value: 3, x: 20),
      ],
    ];
    final series = aggregateLines('g', lines, 'mean', 'minmax', gridSize: 5);
    expect(series.points.map((p) => p.x), [0, 5, 10, 15, 20]);
    expect(series.points.map((p) => p.value), [1, 2, 2, 3, 3]);
    expect(series.points.first.low, isNull, reason: 'only one line covers x=0');
    expect(series.points[1].low, 1);
    expect(aggregateLines('g', const [], 'mean', 'minmax').points, isEmpty);
  });
}
