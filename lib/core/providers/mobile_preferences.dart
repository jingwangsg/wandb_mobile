import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../../features/charts/models/metric_chart_rule.dart';
import '../../features/charts/models/panel_spec.dart';
import '../../features/charts/models/workspace_settings.dart';

class MobilePreferences {
  const MobilePreferences({
    this.theme = ThemeMode.system,
    this.starredMetrics = const {},
    this.runVisibility = const {},
    this.visibleRunLimits = const {},
    this.chartRules = const {},
    this.defaultRules = const {},
    this.customPanels = const {},
    this.grouping = const {},
  });

  final ThemeMode theme;
  final Set<String> starredMetrics;

  /// Project path -> run name -> shown in panels. Runs without an entry follow
  /// the web workspace's run selection, then default to visible.
  final Map<String, Map<String, bool>> runVisibility;

  /// Project path -> how many visible runs the project panels draw.
  final Map<String, int> visibleRunLimits;

  /// Panel key (metric name or panel id) -> rule saved in the app.
  final Map<String, MetricChartRule> chartRules;
  final Map<String, MetricChartRule> defaultRules;

  /// Scope (project or run path) -> panels created in the app.
  final Map<String, List<PanelSpec>> customPanels;

  /// Project path -> run grouping keys (`config:lr`, `run:group`). An entry
  /// overrides the web workspace's grouping; an empty list turns it off.
  final Map<String, List<String>> grouping;

  /// The project- or run-wide rule: the app's own when set, else the web
  /// workspace's, else the app defaults. Both have the same reach, so the
  /// app's explicit choice replaces the web's workspace-wide layer.
  MetricChartRule scopeRuleFor(String scope, WorkspaceSettings? workspace) =>
      defaultRules[scope] ??
      workspace?.workspaceDefaults ??
      MetricChartRule.defaults;

  /// The rule a panel inherits before any per-panel rule saved in the app:
  /// the web's per-panel and section settings for it over [scopeRuleFor].
  MetricChartRule inheritedRuleFor(
    String scope,
    PanelSpec panel,
    WorkspaceSettings? workspace,
  ) {
    final base = scopeRuleFor(scope, workspace);
    return workspace?.apply(base, panel) ?? base;
  }

  MetricChartRule ruleFor(
    String scope,
    PanelSpec panel,
    WorkspaceSettings? workspace,
  ) => chartRules[panel.id] ?? inheritedRuleFor(scope, panel, workspace);

  MobilePreferences copyWith({
    ThemeMode? theme,
    Set<String>? starredMetrics,
    Map<String, Map<String, bool>>? runVisibility,
    Map<String, int>? visibleRunLimits,
    Map<String, MetricChartRule>? chartRules,
    Map<String, MetricChartRule>? defaultRules,
    Map<String, List<PanelSpec>>? customPanels,
    Map<String, List<String>>? grouping,
  }) => MobilePreferences(
    theme: theme ?? this.theme,
    starredMetrics: starredMetrics ?? this.starredMetrics,
    runVisibility: runVisibility ?? this.runVisibility,
    visibleRunLimits: visibleRunLimits ?? this.visibleRunLimits,
    chartRules: chartRules ?? this.chartRules,
    defaultRules: defaultRules ?? this.defaultRules,
    customPanels: customPanels ?? this.customPanels,
    grouping: grouping ?? this.grouping,
  );

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'starredMetrics': starredMetrics.toList(),
    'runVisibility': runVisibility,
    'visibleRunLimits': visibleRunLimits,
    'chartRules': chartRules.map((key, value) => MapEntry(key, value.toJson())),
    'defaultRules': defaultRules.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'customPanels': customPanels.map(
      (key, value) =>
          MapEntry(key, [for (final panel in value) panel.toJson()]),
    ),
    'grouping': grouping,
  };

  factory MobilePreferences.fromJson(Map<String, dynamic> json) =>
      MobilePreferences(
        theme: ThemeMode.values.firstWhere(
          (mode) => mode.name == json['theme'],
          orElse: () => ThemeMode.system,
        ),
        starredMetrics: Set<String>.from(json['starredMetrics'] as List? ?? []),
        runVisibility: {
          // Releases before 2.0.2 stored an opt-out `hiddenRuns` list.
          for (final entry
              in (json['hiddenRuns'] as Map<String, dynamic>? ?? {}).entries)
            entry.key: {for (final run in entry.value as List) '$run': false},
          for (final entry
              in (json['runVisibility'] as Map<String, dynamic>? ?? {}).entries)
            entry.key: Map<String, bool>.from(entry.value as Map),
        },
        visibleRunLimits: Map<String, int>.from(
          json['visibleRunLimits'] as Map? ?? {},
        ),
        chartRules: (json['chartRules'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(
            key,
            MetricChartRule.fromJson(Map<String, dynamic>.from(value as Map)),
          ),
        ),
        defaultRules: (json['defaultRules'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(
            key,
            MetricChartRule.fromJson(Map<String, dynamic>.from(value as Map)),
          ),
        ),
        customPanels: (json['customPanels'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, [
            for (final panel in value as List)
              PanelSpec.fromJson(Map<String, dynamic>.from(panel as Map)),
          ]),
        ),
        grouping: (json['grouping'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, List<String>.from(value as List)),
        ),
      );
}

class MobilePreferencesStore {
  static const boxName = 'mobile_preferences';

  MobilePreferences read(String account) {
    final raw = Hive.box<String>(boxName).get(account);
    return raw == null
        ? const MobilePreferences()
        : MobilePreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> write(String account, MobilePreferences preferences) =>
      Hive.box<String>(boxName).put(account, jsonEncode(preferences.toJson()));
}

class MobilePreferencesNotifier extends StateNotifier<MobilePreferences> {
  MobilePreferencesNotifier(this._store, this._account)
    : super(_store.read(_account));

  final MobilePreferencesStore _store;
  final String _account;

  Future<void> setTheme(ThemeMode theme) => _save(state.copyWith(theme: theme));

  Future<void> toggleMetric(String project, String metric) {
    final stars = {...state.starredMetrics};
    final key = jsonEncode([project, metric]);
    if (!stars.remove(key)) stars.add(key);
    return _save(state.copyWith(starredMetrics: stars));
  }

  Future<void> setRunVisible(String project, String run, bool visible) => _save(
    state.copyWith(
      runVisibility: {
        ...state.runVisibility,
        project: {...?state.runVisibility[project], run: visible},
      },
    ),
  );

  Future<void> setVisibleRunLimit(String project, int limit) => _save(
    state.copyWith(
      visibleRunLimits: {...state.visibleRunLimits, project: limit},
    ),
  );

  Future<void> setRule(String metric, MetricChartRule rule) =>
      _save(state.copyWith(chartRules: {...state.chartRules, metric: rule}));

  Future<void> setDefaults(String scope, MetricChartRule rule) =>
      _save(state.copyWith(defaultRules: {...state.defaultRules, scope: rule}));

  Future<void> resetDefaults(String scope) {
    final rules = {...state.defaultRules}..remove(scope);
    return _save(state.copyWith(defaultRules: rules));
  }

  Future<void> resetRule(String metric) {
    final rules = {...state.chartRules}..remove(metric);
    return _save(state.copyWith(chartRules: rules));
  }

  /// Adds an app panel to [scope], or replaces the one with its id in place.
  Future<void> setCustomPanel(String scope, PanelSpec panel) {
    final existing = state.customPanels[scope] ?? const <PanelSpec>[];
    return _save(
      state.copyWith(
        customPanels: {
          ...state.customPanels,
          scope:
              existing.any((other) => other.id == panel.id)
                  ? [
                    for (final other in existing)
                      other.id == panel.id ? panel : other,
                  ]
                  : [...existing, panel],
        },
      ),
    );
  }

  Future<void> removeCustomPanel(String scope, String id) => _save(
    state.copyWith(
      customPanels: {
        ...state.customPanels,
        scope: [
          for (final existing
              in state.customPanels[scope] ?? const <PanelSpec>[])
            if (existing.id != id) existing,
        ],
      },
    ),
  );

  Future<void> setGrouping(String project, List<String> keys) =>
      _save(state.copyWith(grouping: {...state.grouping, project: keys}));

  /// Drops the app's grouping choice so the web workspace's applies again.
  Future<void> resetGrouping(String project) {
    final grouping = {...state.grouping}..remove(project);
    return _save(state.copyWith(grouping: grouping));
  }

  Future<void> _save(MobilePreferences next) async {
    final previous = state;
    state = next;
    try {
      await _store.write(_account, next);
    } catch (_) {
      if (mounted && identical(state, next)) state = previous;
      rethrow;
    }
  }
}

final mobilePreferencesStoreProvider = Provider<MobilePreferencesStore>(
  (ref) => MobilePreferencesStore(),
);

final mobilePreferencesProvider =
    StateNotifierProvider<MobilePreferencesNotifier, MobilePreferences>((ref) {
      final account = ref.watch(
        authProvider.select((auth) => (auth.baseUrl, auth.user?.id)),
      );
      return MobilePreferencesNotifier(
        ref.watch(mobilePreferencesStoreProvider),
        jsonEncode([account.$1, account.$2]),
      );
    });
