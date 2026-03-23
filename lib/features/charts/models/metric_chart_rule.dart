class MetricChartRule {
  const MetricChartRule({
    this.smoothing = 0,
    this.useAutoMin = true,
    this.min,
    this.useAutoMax = true,
    this.max,
  });

  static const defaults = MetricChartRule();

  final double smoothing;
  final bool useAutoMin;
  final double? min;
  final bool useAutoMax;
  final double? max;

  double? get resolvedMin => useAutoMin ? null : min;
  double? get resolvedMax => useAutoMax ? null : max;

  MetricChartRule copyWith({
    double? smoothing,
    bool? useAutoMin,
    double? min,
    bool clearMin = false,
    bool? useAutoMax,
    double? max,
    bool clearMax = false,
  }) {
    return MetricChartRule(
      smoothing: smoothing ?? this.smoothing,
      useAutoMin: useAutoMin ?? this.useAutoMin,
      min: clearMin ? null : (min ?? this.min),
      useAutoMax: useAutoMax ?? this.useAutoMax,
      max: clearMax ? null : (max ?? this.max),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'smoothing': smoothing,
      'useAutoMin': useAutoMin,
      'min': min,
      'useAutoMax': useAutoMax,
      'max': max,
    };
  }

  factory MetricChartRule.fromJson(Map<String, dynamic> json) {
    return MetricChartRule(
      smoothing: (json['smoothing'] as num?)?.toDouble() ?? 0,
      useAutoMin: json['useAutoMin'] as bool? ?? true,
      min: (json['min'] as num?)?.toDouble(),
      useAutoMax: json['useAutoMax'] as bool? ?? true,
      max: (json['max'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MetricChartRule &&
        other.smoothing == smoothing &&
        other.useAutoMin == useAutoMin &&
        other.min == min &&
        other.useAutoMax == useAutoMax &&
        other.max == max;
  }

  @override
  int get hashCode => Object.hash(smoothing, useAutoMin, min, useAutoMax, max);
}
