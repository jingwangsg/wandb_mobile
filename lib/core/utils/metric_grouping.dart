import '../models/metric_point.dart';

/// A group of metric series sharing the same first-level prefix.
class MetricGroup {
  const MetricGroup({required this.label, required this.series});

  /// Display label for the group (e.g., "train", "val"). Empty string for
  /// ungrouped metrics (rendered as "Other" in the UI).
  final String label;
  final List<MetricSeries> series;
}

/// Groups [seriesList] by the first segment before the first '/'.
/// Keys without '/' are placed in a group with an empty label.
/// Prefixed groups are sorted alphabetically; the ungrouped ("Other") group
/// comes last.
List<MetricGroup> groupSeriesByPrefix(List<MetricSeries> seriesList) {
  final groups = <String, List<MetricSeries>>{};
  for (final s in seriesList) {
    final slashIndex = s.key.indexOf('/');
    final prefix = slashIndex > 0 ? s.key.substring(0, slashIndex) : '';
    (groups[prefix] ??= []).add(s);
  }

  final sortedKeys = groups.keys.where((k) => k.isNotEmpty).toList()..sort();
  final result = <MetricGroup>[
    for (final key in sortedKeys)
      MetricGroup(label: key, series: groups[key]!),
  ];

  // Ungrouped metrics go last.
  final ungrouped = groups[''];
  if (ungrouped != null) {
    result.add(MetricGroup(label: '', series: ungrouped));
  }

  return result;
}
