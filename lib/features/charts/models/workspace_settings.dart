import 'metric_chart_rule.dart';

/// Line plot and run visibility settings read from the user's personal W&B
/// web workspace (a `project-view` spec). The web resolves line plot settings
/// per key: panel override, then section settings, then workspace defaults.
class WorkspaceSettings {
  const WorkspaceSettings({
    required this.linePlot,
    required this.sectionSettings,
    required this.panelOverrides,
    required this.allRunsSelected,
    required this.selectionExceptions,
  });

  factory WorkspaceSettings.fromSpec(Map<String, dynamic> spec) {
    final section = spec['section'] as Map? ?? const {};
    final panelBank = section['panelBankConfig'] as Map? ?? const {};
    final workspaceLinePlot =
        (section['workspaceSettings'] as Map?)?['linePlot'];

    final sections = <String, Map<String, dynamic>>{};
    for (final entry in panelBank['sections'] as List? ?? const []) {
      if (entry is! Map) continue;
      final settings =
          (entry['sectionSettings'] as Map?)?['linePlot'] ??
          entry['localPanelSettings'];
      if (settings is Map) sections['${entry['name']}'] = _active(settings);
    }

    final overrides = <String, Map<String, dynamic>>{};
    final rawOverrides = panelBank['panelConfigOverrides'] as Map? ?? const {};
    for (final entry in rawOverrides.entries) {
      final config = (entry.value as Map?)?['config'];
      if (config is Map) {
        overrides['${entry.key}'] = Map<String, dynamic>.from(config);
      }
    }

    final selections =
        ((section['runSets'] as List?)?.firstOrNull as Map?)?['selections']
            as Map?;
    final tree = selections?['tree'] as List? ?? const [];
    // Grouped run sets nest selection nodes in the tree. The app does not
    // group runs, so such a selection falls back to showing every run.
    final grouped = tree.any((node) => node is! String);

    return WorkspaceSettings(
      linePlot: _active(
        workspaceLinePlot is Map
            ? workspaceLinePlot
            : section['settings'] as Map? ?? const {},
      ),
      sectionSettings: sections,
      panelOverrides: overrides,
      allRunsSelected: grouped || selections == null || selections['root'] != 0,
      selectionExceptions: grouped ? const {} : tree.cast<String>().toSet(),
    );
  }

  /// Legacy specs keep inactive values next to `xAxisActive` and
  /// `smoothingActive` flags; drop them so they cannot override defaults.
  static Map<String, dynamic> _active(Map settings) {
    final active = Map<String, dynamic>.from(settings);
    if (settings['xAxisActive'] == false) active.remove('xAxis');
    if (settings['smoothingActive'] == false) {
      active
        ..remove('smoothingWeight')
        ..remove('smoothingType');
    }
    return active;
  }

  /// Workspace-wide line plot settings.
  final Map<String, dynamic> linePlot;

  /// Section name (the metric prefix before `/`) to its line plot settings.
  final Map<String, Map<String, dynamic>> sectionSettings;

  /// Metric name to the panel config the user changed for that metric.
  final Map<String, Map<String, dynamic>> panelOverrides;

  /// `selections.root == 1`: every run is shown except [selectionExceptions].
  /// Otherwise only [selectionExceptions] are shown.
  final bool allRunsSelected;
  final Set<String> selectionExceptions;

  int? get maxRuns => (linePlot['maxRuns'] as num?)?.toInt();

  bool isRunVisible(String runName) =>
      allRunsSelected
          ? !selectionExceptions.contains(runName)
          : selectionExceptions.contains(runName);

  /// App defaults with the web's workspace-wide line plot settings applied.
  MetricChartRule get workspaceDefaults =>
      _applyLayer(MetricChartRule.defaults, linePlot);

  /// [base] with the web settings closer to [metric] than the workspace
  /// applied on top: its section's settings, then the panel's own overrides.
  MetricChartRule apply(MetricChartRule base, String metric) {
    final slash = metric.indexOf('/');
    // The web files keys without a prefix under a section named Charts.
    final section = slash > 0 ? metric.substring(0, slash) : 'Charts';
    return _applyLayer(
      _applyLayer(base, sectionSettings[section] ?? const {}),
      panelOverrides[metric] ?? const {},
    );
  }

  /// [rule] with the recognised keys of one web settings layer copied over
  /// it. `null` values mean the layer leaves that key alone. Only exponential
  /// smoothing maps onto the app's time weighted EMA; `none` disables it.
  static MetricChartRule _applyLayer(
    MetricChartRule rule,
    Map<String, dynamic> settings,
  ) {
    final xAxis = settings['xAxis'];
    if (xAxis is String && xAxis.isNotEmpty) {
      rule = rule.copyWith(xAxis: xAxis);
    }
    final xMin = settings['xAxisMin'];
    if (xMin is num) {
      rule = rule.copyWith(useAutoXMin: false, xMin: xMin.toDouble());
    }
    final xMax = settings['xAxisMax'];
    if (xMax is num) {
      rule = rule.copyWith(useAutoXMax: false, xMax: xMax.toDouble());
    }
    final yMin = settings['yAxisMin'];
    if (yMin is num) {
      rule = rule.copyWith(useAutoMin: false, min: yMin.toDouble());
    }
    final yMax = settings['yAxisMax'];
    if (yMax is num) {
      rule = rule.copyWith(useAutoMax: false, max: yMax.toDouble());
    }
    final logScale = settings['yLogScale'];
    if (logScale is bool) {
      rule = rule.copyWith(logScale: logScale);
    }
    final type = settings['smoothingType'];
    final weight = settings['smoothingWeight'];
    if (type == 'none') {
      rule = rule.copyWith(smoothing: 0);
    } else if (weight is num &&
        (type == null ||
            type == 'exponential' ||
            type == 'exponentialTimeWeighted')) {
      rule = rule.copyWith(smoothing: weight.toDouble().clamp(0, 0.99));
    }
    return rule;
  }
}
