/// W&B smoothing types. The `smoothing` parameter is a weight in [0, 1) for
/// the exponential types and a size in points for gaussian and average.
const smoothingTypes = [
  'exponentialTimeWeighted',
  'exponential',
  'gaussian',
  'average',
  'none',
];

String smoothingTypeLabel(String type) => switch (type) {
  'exponentialTimeWeighted' => 'Time weighted EMA',
  'exponential' => 'Exponential EMA',
  'gaussian' => 'Gaussian',
  'average' => 'Running average',
  _ => 'No smoothing',
};

/// Web legend positions, as stored in panel configs.
const legendPositions = ['north', 'south', 'east', 'west'];

class MetricChartRule {
  const MetricChartRule({
    this.xAxis = '_step',
    this.smoothing = 0,
    this.smoothingType = 'exponentialTimeWeighted',
    this.showOriginal = true,
    this.ignoreOutliers = false,
    this.pointAggregation = 'bucketing',
    this.legendPosition = 'south',
    this.logScale = false,
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

  /// W&B X-axis key: `_step`, `_runtime`, `_absolute_runtime`, `_timestamp`,
  /// or any numeric history key.
  final String xAxis;
  final double smoothing;
  final String smoothingType;

  /// Draw the unsmoothed line faintly behind the smoothed one.
  final bool showOriginal;

  /// Scale the Y axis to the lines, letting band spikes clip, as the web's
  /// "exclude extreme outliers when scaling" does.
  final bool ignoreOutliers;

  /// `bucketing` (the web's full fidelity) or `sampling`.
  final String pointAggregation;
  final String legendPosition;
  final bool logScale;
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

  bool get smooths => smoothingType != 'none' && smoothing > 0;

  MetricChartRule copyWith({
    String? xAxis,
    double? smoothing,
    String? smoothingType,
    bool? showOriginal,
    bool? ignoreOutliers,
    String? pointAggregation,
    String? legendPosition,
    bool? logScale,
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
      xAxis: xAxis ?? this.xAxis,
      smoothing: smoothing ?? this.smoothing,
      smoothingType: smoothingType ?? this.smoothingType,
      showOriginal: showOriginal ?? this.showOriginal,
      ignoreOutliers: ignoreOutliers ?? this.ignoreOutliers,
      pointAggregation: pointAggregation ?? this.pointAggregation,
      legendPosition: legendPosition ?? this.legendPosition,
      logScale: logScale ?? this.logScale,
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
      'xAxis': xAxis,
      'smoothing': smoothing,
      'smoothingType': smoothingType,
      'showOriginal': showOriginal,
      'ignoreOutliers': ignoreOutliers,
      'pointAggregation': pointAggregation,
      'legendPosition': legendPosition,
      'logScale': logScale,
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
      xAxis: json['xAxis'] as String? ?? '_step',
      smoothing: (json['smoothing'] as num?)?.toDouble() ?? 0,
      smoothingType:
          json['smoothingType'] as String? ?? 'exponentialTimeWeighted',
      showOriginal: json['showOriginal'] as bool? ?? true,
      ignoreOutliers: json['ignoreOutliers'] as bool? ?? false,
      pointAggregation: json['pointAggregation'] as String? ?? 'bucketing',
      legendPosition: json['legendPosition'] as String? ?? 'south',
      logScale: json['logScale'] as bool? ?? false,
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
        other.xAxis == xAxis &&
        other.smoothing == smoothing &&
        other.smoothingType == smoothingType &&
        other.showOriginal == showOriginal &&
        other.ignoreOutliers == ignoreOutliers &&
        other.pointAggregation == pointAggregation &&
        other.legendPosition == legendPosition &&
        other.logScale == logScale &&
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
  int get hashCode => Object.hashAll([
    xAxis,
    smoothing,
    smoothingType,
    showOriginal,
    ignoreOutliers,
    pointAggregation,
    legendPosition,
    logScale,
    useAutoMin,
    min,
    useAutoMax,
    max,
    useAutoXMin,
    xMin,
    useAutoXMax,
    xMax,
  ]);
}
