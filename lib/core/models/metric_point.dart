/// A single data point for chart rendering.
class MetricPoint {
  const MetricPoint({
    required this.step,
    required this.value,
    this.timestamp,
    this.x,
    this.low,
    this.high,
  });

  final num step;
  final double value;
  final DateTime? timestamp;

  /// Position on the chosen X axis, in that axis's units (milliseconds for
  /// wall time), when the server bucketed the history along it.
  final double? x;

  /// Bucket minimum and maximum around [value], when the point is a bucket
  /// of many history rows rather than one row.
  final double? low;
  final double? high;
}

/// A series of metric points for one metric key.
class MetricSeries {
  const MetricSeries({required this.key, required this.points});

  final String key;
  final List<MetricPoint> points;

  bool get isEmpty => points.isEmpty;
  int get length => points.length;
}
