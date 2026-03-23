import 'metric_chart_rule.dart';

enum ChartPreferenceScope { metrics, system }

class RunChartPreferences {
  const RunChartPreferences({
    this.metricsSelectedKeys = const [],
    this.systemSelectedKeys = const [],
    this.metricsRulesByKey = const {},
    this.systemRulesByKey = const {},
  });

  static const empty = RunChartPreferences();

  final List<String> metricsSelectedKeys;
  final List<String> systemSelectedKeys;
  final Map<String, MetricChartRule> metricsRulesByKey;
  final Map<String, MetricChartRule> systemRulesByKey;

  List<String> selectedKeysFor(ChartPreferenceScope scope) {
    switch (scope) {
      case ChartPreferenceScope.metrics:
        return metricsSelectedKeys;
      case ChartPreferenceScope.system:
        return systemSelectedKeys;
    }
  }

  Map<String, MetricChartRule> rulesFor(ChartPreferenceScope scope) {
    switch (scope) {
      case ChartPreferenceScope.metrics:
        return metricsRulesByKey;
      case ChartPreferenceScope.system:
        return systemRulesByKey;
    }
  }

  RunChartPreferences copyWith({
    List<String>? metricsSelectedKeys,
    List<String>? systemSelectedKeys,
    Map<String, MetricChartRule>? metricsRulesByKey,
    Map<String, MetricChartRule>? systemRulesByKey,
  }) {
    return RunChartPreferences(
      metricsSelectedKeys: metricsSelectedKeys ?? this.metricsSelectedKeys,
      systemSelectedKeys: systemSelectedKeys ?? this.systemSelectedKeys,
      metricsRulesByKey: metricsRulesByKey ?? this.metricsRulesByKey,
      systemRulesByKey: systemRulesByKey ?? this.systemRulesByKey,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'metricsSelectedKeys': metricsSelectedKeys,
      'systemSelectedKeys': systemSelectedKeys,
      'metricsRulesByKey': {
        for (final entry in metricsRulesByKey.entries)
          entry.key: entry.value.toJson(),
      },
      'systemRulesByKey': {
        for (final entry in systemRulesByKey.entries)
          entry.key: entry.value.toJson(),
      },
    };
  }

  factory RunChartPreferences.fromJson(Map<String, dynamic> json) {
    return RunChartPreferences(
      metricsSelectedKeys: (json['metricsSelectedKeys'] as List<dynamic>? ??
              const [])
          .map((entry) => entry.toString())
          .toList(growable: false),
      systemSelectedKeys: (json['systemSelectedKeys'] as List<dynamic>? ??
              const [])
          .map((entry) => entry.toString())
          .toList(growable: false),
      metricsRulesByKey: _rulesFromJson(json['metricsRulesByKey']),
      systemRulesByKey: _rulesFromJson(json['systemRulesByKey']),
    );
  }

  static Map<String, MetricChartRule> _rulesFromJson(Object? value) {
    if (value is! Map) return const {};

    return Map<String, MetricChartRule>.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): MetricChartRule.fromJson(
          (entry.value as Map).map(
            (nestedKey, nestedValue) =>
                MapEntry(nestedKey.toString(), nestedValue),
          ),
        ),
    });
  }
}
