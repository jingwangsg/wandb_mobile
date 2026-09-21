import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/core/providers/mobile_preferences.dart';
import 'package:wandb_mobile/features/charts/models/workspace_settings.dart';
import 'package:wandb_mobile/features/charts/presentation/panels_view.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/wandb_line_chart.dart';
import 'package:wandb_mobile/features/charts/providers/panel_providers.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

import 'test_support/mobile_test_support.dart';

class LargeProjectRepository extends RunsRepository {
  LargeProjectRepository({this.runCount = 100})
    : super(GraphqlClient(apiKey: 'fixture'));
  final int runCount;
  final histories = <({String run, String xAxis})>[];

  /// Filters of each run listing request, in order.
  final listings = <Map<String, dynamic>?>[];

  @override
  Future<Map<String, dynamic>> getProjectMetrics({
    required String entity,
    required String project,
  }) async => {
    'keys': {'loss': {}},
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
    return [
      MetricSeries(
        key: keys.single,
        points: const [
          MetricPoint(step: 0, value: 1, x: 5, low: 0.9, high: 1.1),
          MetricPoint(step: 1, value: 0.5, x: 6, low: 0.4, high: 0.6),
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
  }) async {
    final repository = LargeProjectRepository(runCount: runCount);
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

    await tester.tap(find.text('10 of 100 runs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 runs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20 runs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('20 of 100 runs'), findsOneWidget);
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
}
