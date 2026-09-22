import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/utils/downsampling.dart';

void main() {
  final constant = [
    for (var step = 0; step < 20; step++)
      MetricPoint(step: step, value: 3, x: step * 2, low: 2, high: 4),
  ];
  final ramp = [
    for (var step = 0; step < 10; step++)
      MetricPoint(step: step, value: step.toDouble()),
  ];

  test('every smoothing type preserves a constant signal and the band', () {
    for (final type in [
      'exponentialTimeWeighted',
      'exponential',
      'gaussian',
      'average',
    ]) {
      final smoothed = smoothPoints(
        constant,
        type,
        type == 'gaussian' || type == 'average' ? 4 : 0.9,
      );
      expect(smoothed.length, constant.length, reason: type);
      for (final point in smoothed) {
        expect(point.value, closeTo(3, 1e-9), reason: type);
        expect(
          (point.low, point.high, point.x),
          (2.0, 4.0, point.step * 2.0),
          reason: type,
        );
      }
    }
  });

  test('none and a zero parameter return the input unchanged', () {
    expect(smoothPoints(ramp, 'none', 0.9), same(ramp));
    expect(smoothPoints(ramp, 'exponential', 0), same(ramp));
    expect(smoothPoints(ramp, 'average', 1), same(ramp));
  });

  test('the running average is a centred window mean', () {
    final smoothed = runningAverage(ramp, 3);
    expect(smoothed.first.value, 0.5, reason: 'window clipped at the start');
    expect(smoothed[5].value, 5);
    expect(smoothed.last.value, 8.5, reason: 'window clipped at the end');
  });

  test(
    'the exponential average is debiased so it starts at the first value',
    () {
      final smoothed = exponentialSmoothing(ramp, 0.5);
      expect(smoothed.first.value, 0);
      expect(smoothed[1].value, closeTo(2 / 3, 1e-9));
      expect(smoothed.last.value, lessThan(9));
    },
  );

  test('gaussian smoothing pulls a spike towards its neighbours', () {
    final spike = [
      for (var step = 0; step < 9; step++)
        MetricPoint(step: step, value: step == 4 ? 10 : 0),
    ];
    final smoothed = gaussianSmoothing(spike, 1);
    expect(smoothed[4].value, lessThan(10));
    expect(smoothed[3].value, greaterThan(0));
    expect(smoothed[3].value, closeTo(smoothed[5].value, 1e-9));
  });
}
