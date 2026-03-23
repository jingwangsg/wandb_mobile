import 'package:wandb_mobile/features/charts/data/run_chart_preferences_store.dart';
import 'package:wandb_mobile/features/charts/models/metric_chart_rule.dart';
import 'package:wandb_mobile/features/charts/models/run_chart_preferences.dart';

class InMemoryRunChartPreferencesStore extends RunChartPreferencesStore {
  final Map<String, RunChartPreferences> _entries = {};

  @override
  Future<RunChartPreferences> read({
    required String entity,
    required String project,
    required String runName,
  }) async {
    return _entries[_storageKey(entity, project, runName)] ??
        RunChartPreferences.empty;
  }

  @override
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
    _entries[_storageKey(entity, project, runName)] = switch (scope) {
      ChartPreferenceScope.metrics => current.copyWith(
        metricsSelectedKeys: List.unmodifiable(keys),
      ),
      ChartPreferenceScope.system => current.copyWith(
        systemSelectedKeys: List.unmodifiable(keys),
      ),
    };
  }

  @override
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
    final nextRules = {...current.rulesFor(scope), key: rule};
    _entries[_storageKey(entity, project, runName)] = switch (scope) {
      ChartPreferenceScope.metrics => current.copyWith(
        metricsRulesByKey: Map.unmodifiable(nextRules),
      ),
      ChartPreferenceScope.system => current.copyWith(
        systemRulesByKey: Map.unmodifiable(nextRules),
      ),
    };
  }

  String _storageKey(String entity, String project, String runName) {
    return '$entity/$project/$runName';
  }
}
