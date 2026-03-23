import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/metric_chart_rule.dart';
import '../models/run_chart_preferences.dart';

class RunChartPreferencesStore {
  RunChartPreferencesStore();

  static const _boxName = 'run_chart_preferences';
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Hive.initFlutter();
    await Hive.openBox<String>(_boxName);
    _initialized = true;
  }

  Future<RunChartPreferences> read({
    required String entity,
    required String project,
    required String runName,
  }) async {
    final box = await _openBox();
    final raw = box.get(_storageKey(entity, project, runName));
    if (raw == null || raw.isEmpty) {
      return RunChartPreferences.empty;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return RunChartPreferences.empty;
    }

    return RunChartPreferences.fromJson(decoded);
  }

  Future<void> saveSelectedKeys({
    required String entity,
    required String project,
    required String runName,
    required ChartPreferenceScope scope,
    required List<String> keys,
  }) async {
    final current = await read(
      entity: entity,
      project: project,
      runName: runName,
    );
    final next = switch (scope) {
      ChartPreferenceScope.metrics => current.copyWith(
        metricsSelectedKeys: List.unmodifiable(keys),
      ),
      ChartPreferenceScope.system => current.copyWith(
        systemSelectedKeys: List.unmodifiable(keys),
      ),
    };
    await _write(
      entity: entity,
      project: project,
      runName: runName,
      value: next,
    );
  }

  Future<void> saveRule({
    required String entity,
    required String project,
    required String runName,
    required ChartPreferenceScope scope,
    required String key,
    required MetricChartRule rule,
  }) async {
    final current = await read(
      entity: entity,
      project: project,
      runName: runName,
    );
    final nextRules = <String, MetricChartRule>{
      ...current.rulesFor(scope),
      key: rule,
    };

    final next = switch (scope) {
      ChartPreferenceScope.metrics => current.copyWith(
        metricsRulesByKey: Map.unmodifiable(nextRules),
      ),
      ChartPreferenceScope.system => current.copyWith(
        systemRulesByKey: Map.unmodifiable(nextRules),
      ),
    };

    await _write(
      entity: entity,
      project: project,
      runName: runName,
      value: next,
    );
  }

  Future<void> _write({
    required String entity,
    required String project,
    required String runName,
    required RunChartPreferences value,
  }) async {
    final box = await _openBox();
    await box.put(
      _storageKey(entity, project, runName),
      jsonEncode(value.toJson()),
    );
  }

  Future<Box<String>> _openBox() async {
    if (!_initialized) {
      throw StateError(
        'RunChartPreferencesStore.initialize() must run before using the default store.',
      );
    }
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<String>(_boxName);
    }
    return Hive.openBox<String>(_boxName);
  }

  String _storageKey(String entity, String project, String runName) {
    return '$entity/$project/$runName';
  }
}
