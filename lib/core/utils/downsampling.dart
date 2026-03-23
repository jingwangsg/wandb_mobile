import '../models/metric_point.dart';

/// Largest Triangle Three Buckets (LTTB) downsampling algorithm.
/// Reduces [data] to [targetPoints] while preserving visual shape.
/// Returns original data if length <= targetPoints.
List<MetricPoint> lttbDownsample(List<MetricPoint> data, int targetPoints) {
  if (data.length <= 2 || targetPoints < 3 || targetPoints >= data.length) {
    return data;
  }

  final result = <MetricPoint>[data.first];
  final bucketSize = (data.length - 2) / (targetPoints - 2);
  var anchorIndex = 0;

  for (var i = 0; i < targetPoints - 2; i++) {
    final avgRangeStart = ((i + 1) * bucketSize).floor() + 1;
    final avgRangeEnd =
        (((i + 2) * bucketSize).floor() + 1)
            .clamp(avgRangeStart, data.length)
            .toInt();

    var avgX = 0.0;
    var avgY = 0.0;
    final avgRangeLength = avgRangeEnd - avgRangeStart;
    if (avgRangeLength > 0) {
      for (var j = avgRangeStart; j < avgRangeEnd; j++) {
        avgX += data[j].step.toDouble();
        avgY += data[j].value;
      }
      avgX /= avgRangeLength;
      avgY /= avgRangeLength;
    } else {
      avgX = data.last.step.toDouble();
      avgY = data.last.value;
    }

    final rangeOffs = (i * bucketSize).floor() + 1;
    final rangeTo =
        (((i + 1) * bucketSize).floor() + 1)
            .clamp(rangeOffs + 1, data.length - 1)
            .toInt();

    final anchor = data[anchorIndex];
    final anchorX = anchor.step.toDouble();
    final anchorY = anchor.value;

    var maxArea = -1.0;
    var nextAnchorIndex = rangeOffs;

    for (var j = rangeOffs; j < rangeTo; j++) {
      final point = data[j];
      final area =
          ((anchorX - avgX) * (point.value - anchorY) -
                  (anchorX - point.step.toDouble()) * (avgY - anchorY))
              .abs() *
          0.5;
      if (area > maxArea) {
        maxArea = area;
        nextAnchorIndex = j;
      }
    }

    result.add(data[nextAnchorIndex]);
    anchorIndex = nextAnchorIndex;
  }

  result.add(data.last);
  return result;
}

/// Exponential moving average smoothing, matching wandb web implementation.
/// [weight] ranges from 0 (no smoothing) to 0.99 (heavy smoothing).
List<MetricPoint> applySmoothing(List<MetricPoint> data, double weight) {
  if (weight <= 0 || data.isEmpty) return data;

  final smoothed = <MetricPoint>[];
  var last = data.first.value;
  for (final point in data) {
    last = last * weight + point.value * (1 - weight);
    smoothed.add(
      MetricPoint(step: point.step, value: last, timestamp: point.timestamp),
    );
  }
  return smoothed;
}
