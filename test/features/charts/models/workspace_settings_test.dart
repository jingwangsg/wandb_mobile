import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/providers/mobile_preferences.dart';
import 'package:wandb_mobile/features/charts/models/metric_chart_rule.dart';
import 'package:wandb_mobile/features/charts/models/panel_spec.dart';
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
    expect(settings.apply(base, PanelSpec.metric('other/metric')), base);
    expect(settings.maxRuns, 25);
  });

  test('an app scope rule replaces the workspace layer, not closer web '
      'settings', () {
    const scoped = MetricChartRule(smoothing: 0.4, logScale: true);
    const preferences = MobilePreferences(defaultRules: {'team/p': scoped});
    expect(
      preferences.inheritedRuleFor(
        'team/p',
        PanelSpec.metric('other/metric'),
        settings,
      ),
      scoped,
    );
    final rule = preferences.inheritedRuleFor(
      'team/p',
      PanelSpec.metric('train/accuracy'),
      settings,
    );
    expect(rule.xAxis, 'train/global_step');
    expect(rule.smoothingType, 'none');
    expect(rule.smooths, false);
    expect(rule.logScale, true);
    expect(
      preferences.inheritedRuleFor('other', PanelSpec.metric('x'), settings),
      base,
    );
    expect(
      preferences.inheritedRuleFor('other', PanelSpec.metric('x'), null),
      MetricChartRule.defaults,
    );
  });

  test('section settings override the workspace per key', () {
    final rule = settings.apply(base, PanelSpec.metric('train/accuracy'));
    expect(rule.xAxis, 'train/global_step');
    expect(rule.smoothingType, 'none', reason: 'the section turns it off');
    expect(rule.smooths, false);
  });

  test('inactive legacy section keys are ignored', () {
    final rule = settings.apply(base, PanelSpec.metric('eval/accuracy'));
    expect(rule.xAxis, '_runtime');
    expect(rule.smoothing, 0.9);
    expect(rule.smoothingType, 'exponential');
  });

  test('panel overrides win and null ranges stay automatic', () {
    final rule = settings.apply(base, PanelSpec.metric('train/loss'));
    expect(rule.xAxis, 'train/global_step');
    expect(rule.resolvedMax, 0.5);
    expect(rule.useAutoMin, true);
    expect(rule.resolvedXMin, 10);
    expect(rule.useAutoXMax, true);
    expect(rule.logScale, true);
    expect(rule.smoothing, 0.99);
  });

  test('every web smoothing type is carried with its own parameter', () {
    final gaussian = settings.apply(base, PanelSpec.metric('other/gaussian'));
    expect(gaussian.smoothingType, 'gaussian');
    expect(gaussian.smoothing, 5);
    expect(
      settings.apply(base, PanelSpec.metric('train/loss')).smoothingType,
      'exponentialTimeWeighted',
    );
  });

  test('panel overrides carry outliers, legend position and aggregation', () {
    final rule = settings.apply(base, PanelSpec.metric('other/steep'));
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

  test('explicit panels, hidden metrics, grouping and colours are read', () {
    final workspace = WorkspaceSettings.fromSpec({
      'section': {
        'customRunColors': {'run-a': '#ff0000', 'run-b': 'rgb(1,2,3)'},
        'panelBankConfig': {
          'sections': [
            {
              'name': 'Evaluation',
              'sectionSettings': {
                'linePlot': {'xAxis': 'epoch'},
              },
              'panels': [
                {
                  '__id__': 'p1',
                  'viewType': 'Run History Line Plot',
                  'config': {
                    'metrics': ['a', 'b'],
                    'chartTitle': 'A and B',
                    'smoothingWeight': 0.5,
                  },
                },
                {'__id__': 'p2', 'viewType': 'Run Comparer', 'config': {}},
              ],
            },
            {
              'name': 'Hidden Panels',
              'panels': [
                {
                  '__id__': 'h1',
                  'viewType': 'Run History Line Plot',
                  'config': {
                    'metrics': ['noise'],
                  },
                },
                {
                  '__id__': 'h2',
                  'viewType': 'Run History Line Plot',
                  'config': {
                    'metrics': ['a'],
                    'expressions': [r'${a} * 2'],
                  },
                },
              ],
            },
          ],
        },
        'runSets': [
          {
            'grouping': [
              {'section': 'config', 'name': 'lr'},
              {'section': 'run', 'name': 'group'},
            ],
          },
        ],
      },
    });
    expect(workspace.panels.map((p) => p.id), ['p1']);
    expect(workspace.panels.single.displayTitle, 'A and B');
    expect(workspace.hiddenMetrics, {'noise'});
    expect(workspace.grouping, ['config:lr', 'run:group']);
    expect(workspace.runColors, {'run-a': 0xFFFF0000});
    final rule = workspace.apply(
      MetricChartRule.defaults,
      workspace.panels.single,
    );
    expect(rule.xAxis, 'epoch', reason: 'the panel takes its section layer');
    expect(rule.smoothing, 0.5);
  });

  test('group aggregation and band are inherited', () {
    final grouped = WorkspaceSettings.fromSpec({
      'section': {
        'workspaceSettings': {
          'linePlot': {'groupAgg': 'median', 'groupArea': 'stddev'},
        },
      },
    });
    expect(grouped.workspaceDefaults.groupAgg, 'median');
    expect(grouped.workspaceDefaults.groupArea, 'stddev');
    expect(WorkspaceSettings.fromSpec({}).workspaceDefaults.groupAgg, 'mean');
  });

  test("a saved single-metric panel is that metric's auto panel in its web "
      'section, and system panels stay with the hardware charts', () {
    final saved = WorkspaceSettings.fromSpec({
      'section': {
        'panelBankConfig': {
          'sections': [
            {
              'name': 'Evaluation',
              'panels': [
                {
                  '__id__': 'abc',
                  'viewType': 'Run History Line Plot',
                  'config': {
                    'metrics': ['loss'],
                    'chartTitle': 'Training loss',
                    'smoothingWeight': 0.8,
                    'yLogScale': true,
                  },
                },
              ],
            },
            {
              'name': 'System',
              'panels': [
                {
                  '__id__': 'sys',
                  'viewType': 'Run History Line Plot',
                  'config': {
                    'metrics': ['system/gpu.0.gpu', 'system/gpu.1.gpu'],
                  },
                },
              ],
            },
          ],
          'panelConfigOverrides': {
            'loss': {
              'config': {'smoothingWeight': 0.2, 'xAxis': 'epoch'},
            },
          },
        },
      },
    });
    final panel = saved.panels.single;
    expect(
      panel,
      const PanelSpec(
        id: 'loss',
        section: 'Evaluation',
        title: 'Training loss',
        metrics: ['loss'],
      ),
    );
    expect(panel.isAuto, true);
    final rule = saved.apply(MetricChartRule.defaults, panel);
    expect(rule.smoothing, 0.8, reason: 'the saved panel is newer');
    expect(rule.logScale, true);
    expect(rule.xAxis, 'epoch', reason: 'override keys the panel lacks apply');
  });

  test('an empty spec changes nothing', () {
    final empty = WorkspaceSettings.fromSpec({});
    expect(empty.workspaceDefaults, MetricChartRule.defaults);
    expect(empty.apply(base, PanelSpec.metric('loss')), base);
    expect(empty.maxRuns, isNull);
  });
}
