import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../../features/charts/models/metric_chart_rule.dart';

class MobilePreferences {
  const MobilePreferences({
    this.theme = ThemeMode.system,
    this.starredMetrics = const {},
    this.hiddenRuns = const {},
    this.chartRules = const {},
    this.defaultRules = const {},
  });

  final ThemeMode theme;
  final Set<String> starredMetrics;
  final Map<String, Set<String>> hiddenRuns;
  final Map<String, MetricChartRule> chartRules;
  final Map<String, MetricChartRule> defaultRules;

  MetricChartRule ruleFor(String scope, String metric) =>
      chartRules[metric] ?? defaultRules[scope] ?? MetricChartRule.defaults;

  MobilePreferences copyWith({
    ThemeMode? theme,
    Set<String>? starredMetrics,
    Map<String, Set<String>>? hiddenRuns,
    Map<String, MetricChartRule>? chartRules,
    Map<String, MetricChartRule>? defaultRules,
  }) => MobilePreferences(
    theme: theme ?? this.theme,
    starredMetrics: starredMetrics ?? this.starredMetrics,
    hiddenRuns: hiddenRuns ?? this.hiddenRuns,
    chartRules: chartRules ?? this.chartRules,
    defaultRules: defaultRules ?? this.defaultRules,
  );

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'starredMetrics': starredMetrics.toList(),
    'hiddenRuns': hiddenRuns.map((key, value) => MapEntry(key, value.toList())),
    'chartRules': chartRules.map((key, value) => MapEntry(key, value.toJson())),
    'defaultRules': defaultRules.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };

  factory MobilePreferences.fromJson(Map<String, dynamic> json) =>
      MobilePreferences(
        theme: ThemeMode.values.firstWhere(
          (mode) => mode.name == json['theme'],
          orElse: () => ThemeMode.system,
        ),
        starredMetrics: Set<String>.from(json['starredMetrics'] as List? ?? []),
        hiddenRuns: (json['hiddenRuns'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, Set<String>.from(value as List)),
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

  Future<void> toggleRun(String project, String run) {
    final hidden = {...?state.hiddenRuns[project]};
    if (!hidden.remove(run)) hidden.add(run);
    return _save(
      state.copyWith(hiddenRuns: {...state.hiddenRuns, project: hidden}),
    );
  }

  Future<void> setRule(String metric, MetricChartRule rule) =>
      _save(state.copyWith(chartRules: {...state.chartRules, metric: rule}));

  Future<void> setDefaults(String scope, MetricChartRule rule) =>
      _save(state.copyWith(defaultRules: {...state.defaultRules, scope: rule}));

  Future<void> resetRule(String metric) {
    final rules = {...state.chartRules}..remove(metric);
    return _save(state.copyWith(chartRules: rules));
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
