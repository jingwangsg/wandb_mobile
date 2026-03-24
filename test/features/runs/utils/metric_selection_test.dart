import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/features/runs/utils/metric_selection.dart';

void main() {
  test('defaultMetricKeys prefers train headline metrics over system metrics', () {
    final keys = [
      'system/cpu',
      'train/loss',
      'train/accuracy',
      'epoch',
      'val/loss',
    ];

    final selected = defaultMetricKeys(keys, const {});

    expect(selected, contains('train/loss'));
    expect(selected, contains('train/accuracy'));
    expect(selected, isNot(contains('system/cpu')));
  });

  test('historyPointCountForKey only counts numeric entries', () {
    final historyKeyMap = {
      'train/loss': {
        'typeCounts': [
          {'type': 'number', 'count': 300},
          {'type': 'string', 'count': 99},
          {'type': 'number', 'count': 20},
        ],
      },
    };

    expect(historyPointCountForKey('train/loss', historyKeyMap), 320);
  });

  test('defaultSystemKeys prefers GPU and CPU utilization signals', () {
    final selected = defaultSystemKeys([
      'system/process/pid',
      'system/gpu/utilization',
      'system/cpu',
      'system/disk/read_bytes',
    ]);

    expect(
      selected.take(2),
      containsAll(['system/gpu/utilization', 'system/cpu']),
    );
    expect(selected, isNot(contains('system/process/pid')));
  });

  test('systemMetricPriorityScore deprioritizes process/error metrics', () {
    expect(
      systemMetricPriorityScore('system/gpu/utilization'),
      greaterThan(systemMetricPriorityScore('system/process/error_count')),
    );
  });

  test('selectionSummary handles empty, single, and multiple selections', () {
    expect(selectionSummary(const []), 'No metrics selected');
    expect(selectionSummary(const ['train/loss']), 'train/loss');
    expect(
      selectionSummary(const ['train/loss', 'train/accuracy', 'val/loss']),
      'train/loss, +2 more',
    );
  });

  test('selectedSeriesWithFallback preserves selected keys with empty fallback', () {
    final series = selectedSeriesWithFallback(
      const [
        MetricSeries(
          key: 'train/loss',
          points: [MetricPoint(step: 1, value: 0.5)],
        ),
      ],
      const ['train/loss', 'timing/model_forward_avg_ms'],
    );

    expect(series, hasLength(2));
    expect(series[0].key, 'train/loss');
    expect(series[0].points, hasLength(1));
    expect(series[1].key, 'timing/model_forward_avg_ms');
    expect(series[1].points, isEmpty);
  });
}
