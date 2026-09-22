import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/core/providers/mobile_preferences.dart';
import 'package:wandb_mobile/core/theme/colors.dart';
import 'package:wandb_mobile/features/charts/models/workspace_settings.dart';
import 'package:wandb_mobile/features/charts/presentation/panels_view.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/key_picker.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/wandb_line_chart.dart';
import 'package:wandb_mobile/features/charts/providers/panel_providers.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

import 'test_support/mobile_test_support.dart';

class LargeProjectRepository extends RunsRepository {
  LargeProjectRepository({
    this.runCount = 100,
    this.metricKeys = const ['loss'],
  }) : super(GraphqlClient(apiKey: 'fixture'));
  final int runCount;
  final List<String> metricKeys;
  final histories = <({String run, String xAxis})>[];

  /// Filters of each run listing request, in order.
  final listings = <Map<String, dynamic>?>[];

  /// Keys of each history request, in order.
  final requestedKeys = <List<String>>[];

  /// Runs of each sampled (not bucketed) history request, in order.
  final sampled = <String>[];

  @override
  Future<Map<String, dynamic>> getProjectMetrics({
    required String entity,
    required String project,
  }) async => {
    'keys': {for (final key in metricKeys) key: <String, dynamic>{}},
  };

  @override
  Future<PaginatedResult<WandbRun>> getRuns({
    required String entity,
    required String project,
    String? cursor,
    int perPage = 20,
    String? order,
    Map<String, dynamic>? filters,
  }) async {
    listings.add(filters);
    // Honour the by-name filter whether it stands alone or inside `$and`.
    final clauses = [
      ...?(filters?[r'$and'] as List?)?.cast<Map<String, dynamic>>(),
      if (filters != null && !filters.containsKey(r'$and')) filters,
    ];
    final names =
        clauses
            .map((clause) => (clause['name'] as Map?)?[r'$in'] as List?)
            .nonNulls
            .firstOrNull
            ?.cast<String>();
    final matching = [
      for (var index = 0; index < runCount; index++)
        if (names == null || names.contains('run-$index'))
          WandbRun(
            id: '$index',
            name: 'run-$index',
            displayName: 'Run $index',
            state: RunState.finished,
            config: {
              'lr': {'value': index.isEven ? 0.1 : 0.2},
            },
          ),
    ];
    final start = int.parse(cursor ?? '0');
    final end = (start + perPage).clamp(0, matching.length);
    return PaginatedResult(
      items: matching.sublist(start, end),
      endCursor: '$end',
      hasNextPage: end < matching.length,
      totalCount: matching.length,
    );
  }

  @override
  Future<List<MetricSeries>> getBucketedHistory({
    required String entity,
    required String project,
    required String runName,
    required List<String> keys,
    required String xAxis,
  }) async {
    histories.add((run: runName, xAxis: xAxis));
    requestedKeys.add(keys);
    return [
      for (final key in keys)
        MetricSeries(
          key: key,
          points: const [
            MetricPoint(step: 0, value: 1, x: 5, low: 0.9, high: 1.1),
            MetricPoint(step: 1, value: 0.5, x: 6, low: 0.4, high: 0.6),
          ],
        ),
    ];
  }

  @override
  Future<List<MetricSeries>> getSampledHistory({
    required String entity,
    required String project,
    required String runName,
    required List<String> keys,
    required String xAxis,
  }) async {
    sampled.add(runName);
    return [
      for (final key in keys)
        MetricSeries(
          key: key,
          points: const [
            MetricPoint(step: 0, value: 1, x: 5),
            MetricPoint(step: 1, value: 0.5, x: 6),
          ],
        ),
    ];
  }
}

void main() {
  const project = ProjectRef(entity: 'team', project: 'large');

  Future<LargeProjectRepository> pumpPanels(
    WidgetTester tester,
    WorkspaceSettings? workspace, {
    int runCount = 100,
    List<String> metricKeys = const ['loss'],
  }) async {
    final repository = LargeProjectRepository(
      runCount: runCount,
      metricKeys: metricKeys,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...mobileTestOverrides(),
          runsRepositoryProvider.overrideWithValue(repository),
          workspaceSettingsProvider.overrideWith((ref, _) async => workspace),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PanelsView(project: project)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  WandbLineChart chart(WidgetTester tester) =>
      tester.widget<WandbLineChart>(find.byType(WandbLineChart));

  testWidgets('web run selection and panel settings drive project panels', (
    tester,
  ) async {
    final repository = await pumpPanels(
      tester,
      WorkspaceSettings.fromSpec({
        'section': {
          'runSets': [
            {
              'selections': {
                'root': 0,
                // Second page of the 20-run listing.
                'tree': ['run-25'],
              },
            },
          ],
          'panelBankConfig': {
            'panelConfigOverrides': {
              'loss': {
                'config': {
                  'xAxis': 'epoch',
                  'yAxisMax': 2,
                  'smoothingWeight': 0.5,
                },
              },
            },
          },
        },
      }),
    );
    expect(repository.histories, [(run: 'run-25', xAxis: 'epoch')]);
    expect(repository.listings, [
      null,
      {
        'name': {
          r'$in': ['run-25'],
        },
      },
    ], reason: 'one page of the newest runs, then the web selection by name');
    expect(chart(tester).series.map((line) => line.key), ['Run 25 (run-25)']);
    expect(chart(tester).xAxis, 'epoch');
    expect(chart(tester).yAxisMax, 2);
    expect(chart(tester).smoothing, 0.5);
    expect(find.text('1 of 100 runs'), findsOneWidget);

    await tester.tap(find.text('1 of 100 runs'));
    await tester.pumpAndSettle();
    expect(find.text('Run 0'), findsOneWidget);
    await tester.tap(find.byTooltip('Show run in panels').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 100 runs'), findsOneWidget);
    expect(chart(tester).series.map((line) => line.key), [
      'Run 0 (run-0)',
      'Run 25 (run-25)',
    ]);

    // The Runs tab's filters travel with the by-name fetch. The fake ignores
    // displayName filters, so only the request shape is asserted here.
    ProviderScope.containerOf(
      tester.element(find.byType(PanelsView)),
    ).read(runFiltersProvider(project).notifier).setSearchQuery('Run 2');
    await tester.pumpAndSettle();
    expect(repository.listings.last, {
      r'$and': [
        {
          'displayName': {r'$regex': 'Run 2'},
        },
        {
          'name': {
            r'$in': ['run-25'],
          },
        },
      ],
    });

    // A run shown by an app toggle but older than the scanned page is
    // fetched by name too.
    await ProviderScope.containerOf(tester.element(find.byType(PanelsView)))
        .read(mobilePreferencesProvider.notifier)
        .setRunVisible(project.path, 'run-70', true);
    await tester.pumpAndSettle();
    expect((repository.listings.last as Map)[r'$and'][1], {
      'name': {
        r'$in': ['run-25', 'run-70'],
      },
    });
    expect(chart(tester).series.map((line) => line.key), [
      'Run 0 (run-0)',
      'Run 25 (run-25)',
      'Run 70 (run-70)',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a web selection hiding every recent run stops after five pages',
    (tester) async {
      final repository = await pumpPanels(
        tester,
        WorkspaceSettings.fromSpec({
          'section': {
            'runSets': [
              {
                'selections': {
                  'root': 1,
                  'tree': [
                    for (var index = 0; index < 200; index++) 'run-$index',
                  ],
                },
              },
            ],
          },
        }),
        runCount: 200,
      );
      expect(
        repository.listings.length,
        5,
        reason: 'ten pages exist; the scan stops at five',
      );
      expect(repository.histories, isEmpty);
      expect(find.text('0 of 200 runs'), findsOneWidget);
      expect(find.text('No data'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('without a web workspace ten runs are drawn and the limit and '
      'X axis can be changed in the app', (tester) async {
    final repository = await pumpPanels(tester, null);
    expect(repository.histories.length, 10);
    expect(repository.listings, [null]);
    expect(find.text('10 of 100 runs'), findsOneWidget);
    // The page legend names every drawn run and nothing else.
    expect(find.text('Run 9'), findsOneWidget);
    expect(find.text('Run 10'), findsNothing);

    await tester.tap(find.text('10 of 100 runs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 runs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20 runs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('20 of 100 runs'), findsOneWidget);
    expect(find.text('Run 19'), findsOneWidget);
    expect(chart(tester).series.length, 20);
    expect(repository.histories.length, 30);
    expect(repository.listings.length, 2);

    await tester.tap(find.byTooltip('Open panel'));
    await tester.pumpAndSettle();
    expect(chart(tester).xAxis, '_step');
    await tester.tap(find.text('X: Step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wall Time'));
    await tester.pumpAndSettle();
    expect(chart(tester).xAxis, '_timestamp');
    expect(find.text('X: Wall Time'), findsOneWidget);
    expect(
      repository.histories.length,
      50,
      reason: 'the server buckets along the axis, so an axis change refetches',
    );
    expect(repository.histories.last.xAxis, '_timestamp');

    // Any history key is offered. The key list holds 'loss', which is also
    // the panel's own metric.
    await tester.tap(find.text('X: Wall Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('loss').last);
    await tester.pumpAndSettle();
    expect(chart(tester).xAxis, 'loss');
    expect(find.text('X: loss'), findsOneWidget);
    expect(repository.histories.length, 70);
    expect(repository.histories.last.xAxis, 'loss');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'web custom panels draw every metric and expression per run, and runs '
    'can be grouped with a band',
    (tester) async {
      final repository = await pumpPanels(
        tester,
        WorkspaceSettings.fromSpec({
          'section': {
            'panelBankConfig': {
              'sections': [
                {
                  'name': 'Evaluation',
                  'panels': [
                    {
                      '__id__': 'p1',
                      'viewType': 'Run History Line Plot',
                      'config': {
                        'chartTitle': 'Loss and accuracy',
                        'metrics': ['loss'],
                        'metricRegex': 'ac.*',
                        'useMetricRegex': true,
                        'expressions': [r'${loss} * 2'],
                      },
                    },
                  ],
                },
              ],
            },
          },
        }),
        metricKeys: ['loss', 'acc'],
      );
      expect(find.text('Evaluation'), findsOneWidget);
      expect(find.text('Loss and accuracy'), findsOneWidget);
      // Every fetch carries the drawn metrics and the expression inputs.
      expect(
        repository.requestedKeys.where((keys) => keys.length == 2).length,
        greaterThan(0),
      );
      final custom = tester.widget<WandbLineChart>(
        find.descendant(
          of: find.widgetWithText(MetricPanelCard, 'Loss and accuracy'),
          matching: find.byType(WandbLineChart),
        ),
      );
      expect(custom.series.length, 30, reason: '10 runs x (loss, acc, expr)');
      expect(custom.series.first.key, 'Run 0 (run-0) · loss');
      expect(custom.series[2].key, r'Run 0 (run-0) · ${loss} * 2');
      expect(custom.series[2].points.first.value, 2);
      // A run's lines share its colour and differ by dash.
      expect(custom.series.first.color, WandbColors.seriesColor(0).toARGB32());
      expect(custom.series[2].color, custom.series.first.color);
      expect(custom.series[3].color, WandbColors.seriesColor(1).toARGB32());
      expect(custom.series.first.dashArray, isNull);
      expect(custom.series[1].dashArray, [6, 3]);

      // Grouping by a config value replaces runs with aggregate lines.
      await ProviderScope.containerOf(tester.element(find.byType(PanelsView)))
          .read(mobilePreferencesProvider.notifier)
          .setGrouping(project.path, ['config:lr']);
      await tester.pumpAndSettle();
      final grouped = tester.widget<WandbLineChart>(
        find.descendant(
          of: find.widgetWithText(MetricPanelCard, 'Loss and accuracy'),
          matching: find.byType(WandbLineChart),
        ),
      );
      expect(grouped.series.map((line) => line.key), [
        'lr=0.1 · loss',
        'lr=0.1 · acc',
        r'lr=0.1 · ${loss} * 2',
        'lr=0.2 · loss',
        'lr=0.2 · acc',
        r'lr=0.2 · ${loss} * 2',
      ]);
      expect(grouped.series.first.points.first.low, isNotNull);
      expect(grouped.series[3].color, WandbColors.seriesColor(1).toARGB32());
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a panel created in the app is drawn, editable and deletable', (
    tester,
  ) async {
    await pumpPanels(tester, null, metricKeys: ['loss', 'acc']);
    await tester.tap(find.byTooltip('Panel options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add panel'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Chart title'),
      'My panel',
    );
    await tester.tap(find.text('Add metric'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(KeyPicker), matching: find.text('acc')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expression'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, r'${train/loss} - ${train/loss:min}'),
      r'${acc} + 1',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('My panel'), findsOneWidget);
    final chart = tester.widget<WandbLineChart>(
      find.descendant(
        of: find.widgetWithText(MetricPanelCard, 'My panel'),
        matching: find.byType(WandbLineChart),
      ),
    );
    expect(chart.series.length, 20, reason: '10 runs x (acc, expression)');
    expect(chart.series[1].points.first.value, 2);

    await tester.tap(find.byTooltip('Edit panel'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete panel'));
    await tester.tap(find.text('Delete panel'));
    await tester.pumpAndSettle();
    expect(find.text('My panel'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('web sampling, grouping and run colours are inherited, and '
      'grouping changes do not refetch', (tester) async {
    final repository = await pumpPanels(
      tester,
      WorkspaceSettings.fromSpec({
        'section': {
          'workspaceSettings': {
            'linePlot': {
              'pointVisualizationMethod': 'sampling',
              'groupAgg': 'max',
              'groupArea': 'none',
            },
          },
          'runSets': [
            {
              'grouping': [
                {'section': 'config', 'name': 'lr'},
              ],
            },
          ],
          'customRunColors': {'run-0': '#ff0000'},
        },
      }),
    );
    expect(repository.sampled.length, 10);
    expect(repository.histories, isEmpty);
    expect(chart(tester).series.map((line) => line.key), ['lr=0.1', 'lr=0.2']);
    expect(chart(tester).series.first.points.first.low, isNull);
    expect(
      chart(tester).series.first.color,
      WandbColors.seriesColor(0).toARGB32(),
    );
    // The page legend names the groups, not the runs.
    expect(find.text('lr=0.1'), findsOneWidget);
    expect(find.text('Run 0'), findsNothing);

    await ProviderScope.containerOf(tester.element(find.byType(PanelsView)))
        .read(mobilePreferencesProvider.notifier)
        .setGrouping(project.path, const []);
    await tester.pumpAndSettle();
    expect(repository.sampled.length, 10, reason: 'grouping re-aggregates');
    expect(chart(tester).series.first.color, 0xFFFF0000, reason: 'web colour');
    expect(
      chart(tester).series[1].color,
      WandbColors.seriesColor(1).toARGB32(),
    );
    expect(find.text('Run 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a metric the web saved a panel for is drawn once, with that '
      "panel's settings", (tester) async {
    await pumpPanels(
      tester,
      WorkspaceSettings.fromSpec({
        'section': {
          'panelBankConfig': {
            'sections': [
              {
                'name': 'Charts',
                'panels': [
                  {
                    '__id__': 'abc',
                    'viewType': 'Run History Line Plot',
                    'config': {
                      'metrics': ['loss'],
                      'chartTitle': 'Training loss',
                      'smoothingWeight': 0.8,
                    },
                  },
                ],
              },
            ],
          },
        },
      }),
    );
    expect(find.byType(MetricPanelCard), findsOneWidget);
    expect(find.text('Charts'), findsOneWidget);
    expect(find.text('Training loss'), findsOneWidget);
    expect(chart(tester).smoothing, 0.8);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
