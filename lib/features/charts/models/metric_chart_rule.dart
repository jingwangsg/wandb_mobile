class MetricChartRule {
  const MetricChartRule({
    this.smoothing = 0,
    this.useAutoMin = true,
    this.min,
    this.useAutoMax = true,
    this.max,
    this.useAutoXMin = true,
    this.xMin,
    this.useAutoXMax = true,
    this.xMax,
  });

  static const defaults = MetricChartRule();

  final double smoothing;
  final bool useAutoMin;
  final double? min;
  final bool useAutoMax;
  final double? max;
  final bool useAutoXMin;
  final double? xMin;
  final bool useAutoXMax;
  final double? xMax;

  double? get resolvedMin => useAutoMin ? null : min;
  double? get resolvedMax => useAutoMax ? null : max;
  double? get resolvedXMin => useAutoXMin ? null : xMin;
  double? get resolvedXMax => useAutoXMax ? null : xMax;

  MetricChartRule copyWith({
    double? smoothing,
    bool? useAutoMin,
    double? min,
    bool clearMin = false,
    bool? useAutoMax,
    double? max,
    bool clearMax = false,
    bool? useAutoXMin,
    double? xMin,
    bool clearXMin = false,
    bool? useAutoXMax,
    double? xMax,
    bool clearXMax = false,
  }) {
    return MetricChartRule(
      smoothing: smoothing ?? this.smoothing,
      useAutoMin: useAutoMin ?? this.useAutoMin,
      min: clearMin ? null : (min ?? this.min),
      useAutoMax: useAutoMax ?? this.useAutoMax,
      max: clearMax ? null : (max ?? this.max),
      useAutoXMin: useAutoXMin ?? this.useAutoXMin,
      xMin: clearXMin ? null : (xMin ?? this.xMin),
      useAutoXMax: useAutoXMax ?? this.useAutoXMax,
      xMax: clearXMax ? null : (xMax ?? this.xMax),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'smoothing': smoothing,
      'useAutoMin': useAutoMin,
      'min': min,
      'useAutoMax': useAutoMax,
      'max': max,
      'useAutoXMin': useAutoXMin,
      'xMin': xMin,
      'useAutoXMax': useAutoXMax,
      'xMax': xMax,
    };
  }

  factory MetricChartRule.fromJson(Map<String, dynamic> json) {
    return MetricChartRule(
      smoothing: (json['smoothing'] as num?)?.toDouble() ?? 0,
      useAutoMin: json['useAutoMin'] as bool? ?? true,
      min: (json['min'] as num?)?.toDouble(),
      useAutoMax: json['useAutoMax'] as bool? ?? true,
      max: (json['max'] as num?)?.toDouble(),
      useAutoXMin: json['useAutoXMin'] as bool? ?? true,
      xMin: (json['xMin'] as num?)?.toDouble(),
      useAutoXMax: json['useAutoXMax'] as bool? ?? true,
      xMax: (json['xMax'] as num?)?.toDouble(),
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
        other.max == max &&
        other.useAutoXMin == useAutoXMin &&
        other.xMin == xMin &&
        other.useAutoXMax == useAutoXMax &&
        other.xMax == xMax;
  }

  @override
  int get hashCode => Object.hash(
        smoothing, useAutoMin, min, useAutoMax, max,
        useAutoXMin, xMin, useAutoXMax, xMax,
      );
}
