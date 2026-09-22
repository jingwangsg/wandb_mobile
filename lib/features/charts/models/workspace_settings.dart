import '../../runs/utils/metric_selection.dart';
import 'metric_chart_rule.dart';
import 'panel_spec.dart';
import 'run_grouping.dart';

/// Line plot and run visibility settings read from the user's personal W&B
/// web workspace (a `project-view` spec). The web resolves line plot settings
/// per key: panel override, then section settings, then workspace defaults.
class WorkspaceSettings {
  const WorkspaceSettings({
    required this.linePlot,
    required this.sectionSettings,
    required this.panelOverrides,
    required this.panels,
    required this.hiddenMetrics,
    required this.grouping,
    required this.runColors,
    required this.allRunsSelected,
    required this.selectionExceptions,
  });

  factory WorkspaceSettings.fromSpec(Map<String, dynamic> spec) {
    final section = spec['section'] as Map? ?? const {};
    final panelBank = section['panelBankConfig'] as Map? ?? const {};
    final workspaceLinePlot =
        (section['workspaceSettings'] as Map?)?['linePlot'];

    final sections = <String, Map<String, dynamic>>{};
    final overrides = <String, Map<String, dynamic>>{};
    final panels = <PanelSpec>[];
    final hidden = <String>{};
    for (final entry in panelBank['sections'] as List? ?? const []) {
      if (entry is! Map) continue;
      final name = '${entry['name']}';
      final settings =
          (entry['sectionSettings'] as Map?)?['linePlot'] ??
          entry['localPanelSettings'];
      if (settings is Map) sections[name] = _active(settings);
      // Explicit panels are the web's custom line plots. Panels the user
      // moved to "Hidden Panels" stay hidden: a plain single-metric one hides
      // that metric's auto panel too.
      for (final panel in entry['panels'] as List? ?? const []) {
        if (panel is! Map || panel['viewType'] != 'Run History Line Plot') {
          continue;
        }
        final panelSpec = PanelSpec.fromWeb(name, panel);
        // Hardware metrics come from system events, as for auto panels.
        if (panelSpec.metrics.isNotEmpty &&
            panelSpec.metrics.every(isSystemMetric)) {
          continue;
        }
        if (name == 'Hidden Panels') {
          if (panelSpec.isSingleMetric) hidden.add(panelSpec.metrics.single);
          continue;
        }
        final config = Map<String, dynamic>.from(
          panel['config'] as Map? ?? const {},
        );
        // A saved workspace holds one single-metric panel per metric: that
        // is the metric's auto panel, placed in this section and titled if
        // the user renamed it, and its config is the metric's override.
        final spec =
            panelSpec.isSingleMetric
                ? PanelSpec(
                  id: panelSpec.metrics.single,
                  section: name,
                  title: panelSpec.title,
                  metrics: panelSpec.metrics,
                )
                : panelSpec;
        panels.add(spec);
        overrides[spec.id] = config;
      }
    }

    // Auto-panel overrides predate a panel being saved; the saved panel's
    // config is newer, so it wins key by key.
    final rawOverrides = panelBank['panelConfigOverrides'] as Map? ?? const {};
    for (final entry in rawOverrides.entries) {
      final config = (entry.value as Map?)?['config'];
      if (config is Map) {
        overrides['${entry.key}'] = {
          ...Map<String, dynamic>.from(config),
          ...?overrides['${entry.key}'],
        };
      }
    }

    final runSet = (section['runSets'] as List?)?.firstOrNull as Map?;
    final grouping = [
      for (final key in runSet?['grouping'] as List? ?? const [])
        if (key is Map && key['name'] != null)
          '${key['section'] ?? 'config'}:${key['name']}',
    ];
    final runColors = <String, int>{};
    for (final entry
        in (section['customRunColors'] as Map? ?? const {}).entries) {
      final color = _argb('${entry.value}');
      if (color != null) runColors['${entry.key}'] = color;
    }

    final selections = runSet?['selections'] as Map?;
    final tree = selections?['tree'] as List? ?? const [];
    // A run set grouped on the web nests selection nodes keyed by group
    // value, which a by-run-name selection cannot express, so every run
    // counts as selected.
    final grouped = tree.any((node) => node is! String);

    return WorkspaceSettings(
      linePlot: _active(
        workspaceLinePlot is Map
            ? workspaceLinePlot
            : section['settings'] as Map? ?? const {},
      ),
      sectionSettings: sections,
      panelOverrides: overrides,
      panels: panels,
      hiddenMetrics: hidden,
      grouping: grouping,
      runColors: runColors,
      allRunsSelected: grouped || selections == null || selections['root'] != 0,
      selectionExceptions: grouped ? const {} : tree.cast<String>().toSet(),
    );
  }

  /// Web run colours are `#rrggbb`; anything else is left to the palette.
  static int? _argb(String value) {
    final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value.trim());
    return match == null ? null : 0xFF000000 | int.parse(match[1]!, radix: 16);
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

  /// Panel key (metric name for auto panels, `__id__` for explicit ones) to
  /// the config the user set for it.
  final Map<String, Map<String, dynamic>> panelOverrides;

  /// The web's explicit line plots, outside "Hidden Panels".
  final List<PanelSpec> panels;

  /// Metrics whose auto panel the user hid on the web.
  final Set<String> hiddenMetrics;

  /// Run grouping keys as `section:name`, e.g. `config:lr`, `run:group`.
  final List<String> grouping;

  /// Run name to its custom colour (ARGB).
  final Map<String, int> runColors;

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

  /// [base] with the web settings closer to [panel] than the workspace
  /// applied on top: its section's settings, then the panel's own config.
  MetricChartRule apply(MetricChartRule base, PanelSpec panel) => _applyLayer(
    _applyLayer(base, sectionSettings[panel.section] ?? const {}),
    panelOverrides[panel.id] ?? const {},
  );

  /// [rule] with the recognised keys of one web settings layer copied over
  /// it. `null` values mean the layer leaves that key alone.
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
    if (type is String && smoothingTypes.contains(type)) {
      rule = rule.copyWith(smoothingType: type);
    }
    final weight = settings['smoothingWeight'];
    if (weight is num && weight.isFinite) {
      rule = rule.copyWith(smoothing: weight.toDouble());
    }
    // Workspace and section layers store ignoreOutliers; panel overrides
    // store excludeOutliers as a string.
    final outliers = switch (settings['excludeOutliers']) {
      'exclude-outliers' => true,
      'include-outliers' => false,
      _ => settings['ignoreOutliers'],
    };
    if (outliers is bool) rule = rule.copyWith(ignoreOutliers: outliers);
    final points = settings['pointVisualizationMethod'];
    if (points is String) {
      rule = rule.copyWith(
        pointAggregation: points == 'sampling' ? 'sampling' : 'bucketing',
      );
    }
    final legend = settings['legendPosition'];
    if (legend is String && legendPositions.contains(legend)) {
      rule = rule.copyWith(legendPosition: legend);
    }
    final groupAgg = settings['groupAgg'];
    if (groupAgg is String && groupAggregations.contains(groupAgg)) {
      rule = rule.copyWith(groupAgg: groupAgg);
    }
    final groupArea = settings['groupArea'];
    if (groupArea is String && groupAreas.contains(groupArea)) {
      rule = rule.copyWith(groupArea: groupArea);
    }
    return rule;
  }
}
