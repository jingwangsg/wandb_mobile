import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/utils/downsampling.dart';

List<MetricPoint> _buildPoints(int count) {
  return List.generate(
    count,
    (index) => MetricPoint(step: index, value: (index % 11).toDouble()),
  );
}

void main() {
  group('lttbDownsample', () {
    test('downsamples 500 points to 300 points without dropping endpoints', () {
      final data = _buildPoints(500);

      final result = lttbDownsample(data, 300);

      expect(result, hasLength(300));
      expect(result.first.step, data.first.step);
      expect(result.last.step, data.last.step);
    });

    test('downsamples 301 points to 300 points without throwing', () {
      final data = _buildPoints(301);

      expect(() => lttbDownsample(data, 300), returnsNormally);
      expect(lttbDownsample(data, 300), hasLength(300));
    });

    test('returns original data when target is below three', () {
      final data = _buildPoints(10);

      final result = lttbDownsample(data, 2);

      expect(result, same(data));
    });

    test(
      'returns original data when target is not lower than source length',
      () {
        final data = _buildPoints(10);

        expect(lttbDownsample(data, 10), same(data));
        expect(lttbDownsample(data, 20), same(data));
      },
    );

    test('returns original data when there are two points or fewer', () {
      final data = _buildPoints(2);

      final result = lttbDownsample(data, 3);

      expect(result, same(data));
    });
  });
}
