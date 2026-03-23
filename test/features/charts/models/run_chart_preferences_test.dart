import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/features/charts/models/metric_chart_rule.dart';
import 'package:wandb_mobile/features/charts/models/run_chart_preferences.dart';

void main() {
  test('serializes and deserializes chart preferences', () {
    const rule = MetricChartRule(
      smoothing: 0.25,
      useAutoMin: false,
      min: 0.1,
      useAutoMax: false,
      max: 0.9,
    );
    const preferences = RunChartPreferences(
      metricsSelectedKeys: ['train/loss'],
      systemSelectedKeys: ['system/gpu/utilization'],
      metricsRulesByKey: {'train/loss': rule},
      systemRulesByKey: {'system/gpu/utilization': rule},
    );

    final restored = RunChartPreferences.fromJson(preferences.toJson());

    expect(restored.metricsSelectedKeys, ['train/loss']);
    expect(restored.systemSelectedKeys, ['system/gpu/utilization']);
    expect(restored.metricsRulesByKey['train/loss'], rule);
    expect(restored.systemRulesByKey['system/gpu/utilization'], rule);
  });
}
