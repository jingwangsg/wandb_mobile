import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/providers/mobile_preferences.dart';
import 'package:wandb_mobile/features/charts/models/metric_chart_rule.dart';
import 'package:wandb_mobile/features/charts/models/workspace_settings.dart';

void main() {
  // Trimmed from real nw-nwuser<name>-w specs: workspace defaults, one section
  // in the current format, one legacy section, and auto-panel overrides.
  final settings = WorkspaceSettings.fromSpec({
    'section': {
      'workspaceSettings': {
        'linePlot': {
          'xAxis': '_runtime',
          'smoothingWeight': 0.2,
          'smoothingType': 'exponential',
          'maxRuns': 25,
          'ignoreOutliers': true,
          'pointVisualizationMethod': 'sampling',
        },
      },
      'panelBankConfig': {
        'sections': [
          {
            'name': 'train',
            'sectionSettings': {
              'linePlot': {
                'xAxis': 'train/global_step',
                'smoothingType': 'none',
              },
            },
          },
          {
            'name': 'eval',
            'localPanelSettings': {
              'xAxis': 'eval/step',
              'xAxisActive': false,
              'smoothingWeight': 0.9,
              'smoothingActive': true,
            },
          },
        ],
        'panelConfigOverrides': {
          'train/loss': {
            'config': {
              'metrics': ['train/loss'],
              'yAxisMax': 0.5,
              'yAxisMin': null,
              'xAxisMin': 10,
              'yLogScale': true,
              'smoothingWeight': 0.99,
              'smoothingType': 'exponentialTimeWeighted',
            },
          },
          'other/gaussian': {
            'config': {'smoothingType': 'gaussian', 'smoothingWeight': 5},
          },
          'other/steep': {
            'config': {
              'smoothingWeight': 1,
              'excludeOutliers': 'include-outliers',
              'legendPosition': 'east',
              'pointVisualizationMethod': 'bucketing-gorilla',
            },
          },
        },
      },
      'runSets': [
        {
          'selections': {
            'root': 0,
            'tree': ['run-a', 'run-b'],
          },
        },
      ],
    },
  });
  final base = settings.workspaceDefaults;

  test('workspace defaults apply to metrics without closer settings', () {
    expect(base.xAxis, '_runtime');
    expect(base.smoothing, 0.2);
    expect(base.smoothingType, 'exponential');
    expect(base.ignoreOutliers, true);
    expect(base.pointAggregation, 'sampling');
    expect(base.legendPosition, 'south');
    expect(base.useAutoMin, true);
    expect(settings.apply(base, 'other/metric'), base);
    expect(settings.maxRuns, 25);
  });

  test('an app scope rule replaces the workspace layer, not closer web '
      'settings', () {
    const scoped = MetricChartRule(smoothing: 0.4, logScale: true);
    const preferences = MobilePreferences(defaultRules: {'team/p': scoped});
    expect(
      preferences.inheritedRuleFor('team/p', 'other/metric', settings),
      scoped,
    );
    final rule = preferences.inheritedRuleFor(
      'team/p',
      'train/accuracy',
      settings,
    );
    expect(rule.xAxis, 'train/global_step');
    expect(rule.smoothingType, 'none');
    expect(rule.smooths, false);
    expect(rule.logScale, true);
    expect(preferences.inheritedRuleFor('other', 'x', settings), base);
    expect(
      preferences.inheritedRuleFor('other', 'x', null),
      MetricChartRule.defaults,
    );
  });

  test('section settings override the workspace per key', () {
    final rule = settings.apply(base, 'train/accuracy');
    expect(rule.xAxis, 'train/global_step');
    expect(rule.smoothingType, 'none', reason: 'the section turns it off');
    expect(rule.smooths, false);
  });

  test('inactive legacy section keys are ignored', () {
    final rule = settings.apply(base, 'eval/accuracy');
    expect(rule.xAxis, '_runtime');
    expect(rule.smoothing, 0.9);
    expect(rule.smoothingType, 'exponential');
  });

  test('panel overrides win and null ranges stay automatic', () {
    final rule = settings.apply(base, 'train/loss');
    expect(rule.xAxis, 'train/global_step');
    expect(rule.resolvedMax, 0.5);
    expect(rule.useAutoMin, true);
    expect(rule.resolvedXMin, 10);
    expect(rule.useAutoXMax, true);
    expect(rule.logScale, true);
    expect(rule.smoothing, 0.99);
  });

  test('every web smoothing type is carried with its own parameter', () {
    final gaussian = settings.apply(base, 'other/gaussian');
    expect(gaussian.smoothingType, 'gaussian');
    expect(gaussian.smoothing, 5);
    expect(
      settings.apply(base, 'train/loss').smoothingType,
      'exponentialTimeWeighted',
    );
  });

  test('panel overrides carry outliers, legend position and aggregation', () {
    final rule = settings.apply(base, 'other/steep');
    expect(rule.smoothing, 1);
    expect(rule.ignoreOutliers, false, reason: 'include-outliers wins');
    expect(rule.legendPosition, 'east');
    expect(rule.pointAggregation, 'bucketing');
  });

  test('root 0 selections show only listed runs and root 1 hides them', () {
    expect(settings.isRunVisible('run-a'), true);
    expect(settings.isRunVisible('run-c'), false);
    final inverted = WorkspaceSettings.fromSpec({
      'section': {
        'runSets': [
          {
            'selections': {
              'root': 1,
              'tree': ['run-a'],
            },
          },
        ],
      },
    });
    expect(inverted.isRunVisible('run-a'), false);
    expect(inverted.isRunVisible('run-c'), true);
    expect(WorkspaceSettings.fromSpec({}).isRunVisible('anything'), true);
  });

  test('a grouped run set selection shows every run', () {
    final grouped = WorkspaceSettings.fromSpec({
      'section': {
        'runSets': [
          {
            'selections': {
              'root': 0,
              'tree': [
                {
                  'root': 1,
                  'tree': ['run-a'],
                },
              ],
            },
          },
        ],
      },
    });
    expect(grouped.isRunVisible('run-a'), true);
    expect(grouped.isRunVisible('run-c'), true);
  });

  test('legacy workspace settings honour their active flags', () {
    final legacy = WorkspaceSettings.fromSpec({
      'section': {
        'settings': {
          'xAxis': 'epoch',
          'xAxisActive': false,
          'smoothingWeight': 0.5,
          'smoothingActive': false,
          'maxRuns': 10,
        },
      },
    });
    expect(legacy.workspaceDefaults, MetricChartRule.defaults);
    expect(legacy.maxRuns, 10);
  });

  test('an empty spec changes nothing', () {
    final empty = WorkspaceSettings.fromSpec({});
    expect(empty.workspaceDefaults, MetricChartRule.defaults);
    expect(empty.apply(base, 'loss'), base);
    expect(empty.maxRuns, isNull);
  });
}
