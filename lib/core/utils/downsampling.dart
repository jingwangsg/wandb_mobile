import 'dart:math' as math;

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

/// Debiased TWEMA; normalize step distances so sampling density does not set the smoothing strength.
List<MetricPoint> timeWeightedSmoothing(List<MetricPoint> data, double weight) {
  if (weight <= 0 || data.length < 2) return data;
  final range = (data.last.step - data.first.step).toDouble();
  if (range <= 0) return data;
  final smoothing = math.min(math.sqrt(weight.clamp(0, 0.99)), 0.999);
  var last = 0.0;
  var debias = 0.0;
  return data.indexed.map((entry) {
    final (index, point) = entry;
    final previous = data[index == 0 ? 0 : index - 1];
    final distance = math.max(0, (point.step - previous.step) / range * 1000);
    final decay = math.pow(smoothing, distance).toDouble();
    last = last * decay + point.value;
    debias = debias * decay + 1;
    return _withValue(point, last / debias);
  }).toList();
}

/// The web's debiased exponential moving average.
List<MetricPoint> exponentialSmoothing(List<MetricPoint> data, double weight) {
  if (weight <= 0 || data.length < 2) return data;
  final w = weight.clamp(0, 0.999);
  var last = 0.0;
  var debias = 0.0;
  return [
    for (final point in data)
      _withValue(
        point,
        (last = last * w + point.value * (1 - w)) /
            (debias = debias * w + (1 - w)),
      ),
  ];
}

/// Gaussian kernel over neighbouring points; [sigma] is in points.
List<MetricPoint> gaussianSmoothing(List<MetricPoint> data, double sigma) {
  if (sigma <= 0 || data.length < 2) return data;
  final radius = (3 * sigma).ceil();
  return [
    for (final (index, point) in data.indexed)
      _withValue(point, () {
        var sum = 0.0;
        var norm = 0.0;
        final start = math.max(0, index - radius);
        final end = math.min(data.length - 1, index + radius);
        for (var j = start; j <= end; j++) {
          final k = math.exp(
            -((j - index) * (j - index)) / (2 * sigma * sigma),
          );
          sum += data[j].value * k;
          norm += k;
        }
        return sum / norm;
      }()),
  ];
}

/// Mean of a centred window of [window] points.
List<MetricPoint> runningAverage(List<MetricPoint> data, int window) {
  if (window <= 1 || data.length < 2) return data;
  final before = window ~/ 2;
  return [
    for (final (index, point) in data.indexed)
      _withValue(point, () {
        final start = math.max(0, index - before);
        final end = math.min(data.length - 1, index - before + window - 1);
        var sum = 0.0;
        for (var j = start; j <= end; j++) {
          sum += data[j].value;
        }
        return sum / (end - start + 1);
      }()),
  ];
}

/// Applies the web smoothing [type] with its [parameter]; `none` or a zero
/// parameter returns [data] itself.
List<MetricPoint> smoothPoints(
  List<MetricPoint> data,
  String type,
  double parameter,
) => switch (type) {
  'exponentialTimeWeighted' => timeWeightedSmoothing(data, parameter),
  'exponential' => exponentialSmoothing(data, parameter),
  'gaussian' => gaussianSmoothing(data, parameter),
  'average' => runningAverage(data, parameter.round()),
  _ => data,
};

/// The band stays raw: only the line is smoothed, as on the web.
MetricPoint _withValue(MetricPoint point, double value) => MetricPoint(
  step: point.step,
  value: value,
  timestamp: point.timestamp,
  x: point.x,
  low: point.low,
  high: point.high,
);
