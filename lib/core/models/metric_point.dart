/// A single data point for chart rendering.
class MetricPoint {
  const MetricPoint({
    required this.step,
    required this.value,
    this.timestamp,
  });

  final num step;
  final double value;
  final DateTime? timestamp;
}

/// A series of metric points for one metric key.
class MetricSeries {
  const MetricSeries({
    required this.key,
    required this.points,
  });

  final String key;
  final List<MetricPoint> points;

  bool get isEmpty => points.isEmpty;
  int get length => points.length;
}
