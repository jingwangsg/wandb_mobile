import 'package:flutter/foundation.dart';

import 'metric_expression.dart';

/// One line plot. Auto panels draw a single metric; the web's explicit
/// panels and the app's own panels can draw several metrics, every metric
/// matching a regex, and expressions over metrics.
class PanelSpec {
  const PanelSpec({
    required this.id,
    required this.section,
    this.title = '',
    this.metrics = const [],
    this.metricRegex,
    this.expressions = const [],
  });

  PanelSpec.metric(String metric)
    : this(id: metric, section: sectionOf(metric), metrics: [metric]);

  /// A web panel node: `{__id__, viewType, config}`.
  factory PanelSpec.fromWeb(String section, Map panel) {
    final config = panel['config'] as Map? ?? const {};
    return PanelSpec(
      id: '${panel['__id__']}',
      section: section,
      title: config['chartTitle'] as String? ?? '',
      metrics: (config['metrics'] as List? ?? const []).cast<String>(),
      metricRegex:
          config['useMetricRegex'] == true
              ? config['metricRegex'] as String?
              : null,
      expressions: (config['expressions'] as List? ?? const []).cast<String>(),
    );
  }

  factory PanelSpec.fromJson(Map<String, dynamic> json) => PanelSpec(
    id: json['id'] as String,
    section: json['section'] as String? ?? 'Custom',
    title: json['title'] as String? ?? '',
    metrics: (json['metrics'] as List? ?? const []).cast<String>(),
    metricRegex: json['metricRegex'] as String?,
    expressions: (json['expressions'] as List? ?? const []).cast<String>(),
  );

  /// Rule key: the metric name for auto panels, the web `__id__` or an app
  /// id otherwise.
  final String id;

  /// Web section name; for auto panels the metric prefix (the web files
  /// keys without a prefix under `Charts`).
  final String section;
  final String title;
  final List<String> metrics;
  final String? metricRegex;
  final List<String> expressions;

  bool get isSingleMetric =>
      metricRegex == null && expressions.isEmpty && metrics.length == 1;

  /// The auto panel of one metric, keyed by that metric.
  bool get isAuto => isSingleMetric && metrics.single == id;

  static String sectionOf(String metric) {
    final slash = metric.indexOf('/');
    return slash > 0 ? metric.substring(0, slash) : 'Charts';
  }

  /// Metrics drawn as lines: the explicit ones plus catalog keys matching
  /// [metricRegex]. An invalid regex matches nothing.
  List<String> resolveMetrics(Iterable<String> catalog) {
    final drawn = <String>{...metrics};
    final regex = metricRegex;
    if (regex != null && regex.isNotEmpty) {
      try {
        final pattern = RegExp(regex);
        drawn.addAll(catalog.where(pattern.hasMatch));
      } on FormatException {
        // Nothing to add.
      }
    }
    return drawn.toList();
  }

  List<MetricExpression> get validExpressions => [
    for (final source in expressions)
      if (_tryParse(source) case final parsed?) parsed,
  ];

  static MetricExpression? _tryParse(String source) {
    try {
      return MetricExpression.parse(source);
    } on FormatException {
      return null;
    }
  }

  String get displayTitle =>
      title.isNotEmpty
          ? title
          : [
            ...metrics,
            if (metricRegex != null && metricRegex!.isNotEmpty)
              '/$metricRegex/',
            ...expressions,
          ].join(', ');

  Map<String, dynamic> toJson() => {
    'id': id,
    'section': section,
    'title': title,
    'metrics': metrics,
    'metricRegex': metricRegex,
    'expressions': expressions,
  };

  @override
  bool operator ==(Object other) =>
      other is PanelSpec &&
      other.id == id &&
      other.section == section &&
      other.title == title &&
      listEquals(other.metrics, metrics) &&
      other.metricRegex == metricRegex &&
      listEquals(other.expressions, expressions);

  @override
  int get hashCode => Object.hash(
    id,
    section,
    title,
    Object.hashAll(metrics),
    metricRegex,
    Object.hashAll(expressions),
  );
}
