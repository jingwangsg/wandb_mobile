import 'dart:math' as math;

import '../../../core/models/metric_point.dart';
import '../../../core/models/run.dart';

/// Web group aggregations and band areas for grouped runs.
const groupAggregations = ['mean', 'min', 'max', 'median'];
const groupAreas = ['minmax', 'stddev', 'none'];

/// Run fields offered as grouping keys besides config entries.
const runGroupingKeys = [
  'run:group',
  'run:jobType',
  'run:state',
  'run:username',
];

/// Value of a grouping key for a run. `config:a.b` reads the run config,
/// `run:group` a run field; missing values group under a dash.
String groupValue(WandbRun run, String key) {
  final colon = key.indexOf(':');
  final section = key.substring(0, colon);
  final name = key.substring(colon + 1);
  if (section == 'run') {
    return switch (name) {
          'group' => run.group,
          'jobType' => run.jobType,
          'state' => run.state.name,
          'username' => run.userName,
          _ => null,
        } ??
        '-';
  }
  Object? value = run.config;
  for (final (index, part) in name.split('.').indexed) {
    if (value is! Map) return '-';
    value = value[part];
    // Top-level config entries wrap their value: {"lr": {"value": 0.1}}.
    if (index == 0 && value is Map && value.containsKey('value')) {
      value = value['value'];
    }
  }
  return value == null ? '-' : '$value';
}

String groupLabel(WandbRun run, List<String> keys) => [
  for (final key in keys)
    '${key.substring(key.indexOf(':') + 1)}=${groupValue(run, key)}',
].join(', ');

/// One line for several runs: every line is resampled onto a shared grid by
/// linear interpolation, then combined per grid point with [aggregation];
/// [area] draws the spread as the band.
MetricSeries aggregateLines(
  String key,
  List<List<MetricPoint>> lines,
  String aggregation,
  String area, {
  int gridSize = 300,
}) {
  final sorted = [
    for (final line in lines)
      if (line.isNotEmpty)
        [...line]..sort((a, b) => _xOf(a).compareTo(_xOf(b))),
  ];
  if (sorted.isEmpty) return MetricSeries(key: key, points: const []);
  final low = sorted.map((line) => _xOf(line.first)).reduce(math.min);
  final high = sorted.map((line) => _xOf(line.last)).reduce(math.max);
  final steps = high > low ? gridSize : 1;
  final points = <MetricPoint>[];
  for (var i = 0; i < steps; i++) {
    final x = steps == 1 ? low : low + (high - low) * i / (steps - 1);
    final values = [
      for (final line in sorted)
        if (_interpolate(line, x) case final value?) value,
    ]..sort();
    if (values.isEmpty) continue;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final value = switch (aggregation) {
      'min' => values.first,
      'max' => values.last,
      'median' => values[values.length ~/ 2],
      _ => mean,
    };
    double? bandLow;
    double? bandHigh;
    if (values.length > 1 && area == 'minmax') {
      bandLow = values.first;
      bandHigh = values.last;
    } else if (values.length > 1 && area == 'stddev') {
      final variance =
          values.fold(0.0, (sum, v) => sum + (v - mean) * (v - mean)) /
          values.length;
      final deviation = math.sqrt(variance);
      bandLow = mean - deviation;
      bandHigh = mean + deviation;
    }
    points.add(
      MetricPoint(step: x, value: value, x: x, low: bandLow, high: bandHigh),
    );
  }
  return MetricSeries(key: key, points: points);
}

double _xOf(MetricPoint point) => (point.x ?? point.step).toDouble();

double? _interpolate(List<MetricPoint> line, double x) {
  if (x < _xOf(line.first) || x > _xOf(line.last)) return null;
  var lo = 0;
  var hi = line.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) ~/ 2;
    if (_xOf(line[mid]) <= x) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final a = line[lo];
  final b = line[hi];
  if (_xOf(b) == _xOf(a)) return a.value;
  final t = (x - _xOf(a)) / (_xOf(b) - _xOf(a));
  return a.value + (b.value - a.value) * t;
}
