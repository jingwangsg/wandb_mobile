import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/features/charts/models/workspace_settings.dart';
import 'package:wandb_mobile/features/charts/presentation/panels_view.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/wandb_line_chart.dart';
import 'package:wandb_mobile/features/charts/providers/panel_providers.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

import 'test_support/mobile_test_support.dart';

class LargeProjectRepository extends RunsRepository {
  LargeProjectRepository() : super(GraphqlClient(apiKey: 'fixture'));
  final histories = <({String run, String? xKey})>[];
  var pages = 0;

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
    pages++;
    final start = int.parse(cursor ?? '0');
    final end = (start + perPage).clamp(0, 100);
    return PaginatedResult(
      items: [
        for (var index = start; index < end; index++)
          WandbRun(
            id: '$index',
            name: 'run-$index',
            displayName: 'Run $index',
            state: RunState.finished,
          ),
      ],
      endCursor: '$end',
      hasNextPage: end < 100,
      totalCount: 100,
    );
  }

  @override
  Future<List<MetricSeries>> getSampledHistory({
    required String entity,
    required String project,
    required String runName,
    required List<String> keys,
    String? xKey,
    int samples = 500,
  }) async {
    histories.add((run: runName, xKey: xKey));
    return [
      MetricSeries(
        key: keys.single,
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
    WorkspaceSettings? workspace,
  ) async {
    final repository = LargeProjectRepository();
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
    expect(repository.histories, [(run: 'run-25', xKey: 'epoch')]);
    expect(
      repository.pages,
      5,
      reason: 'a sparse web selection pages through the whole project',
    );
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
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a web workspace ten runs are drawn and the limit and '
      'X axis can be changed in the app', (tester) async {
    final repository = await pumpPanels(tester, null);
    expect(repository.histories.length, 10);
    expect(repository.pages, 1);
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
    expect(repository.pages, 2);

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
      30,
      reason: 'timestamp axes are already part of every history request',
    );

    // Any history key is offered; picking one refetches with it. The key
    // list holds 'loss', which is also the panel's own metric.
    await tester.tap(find.text('X: Wall Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('loss').last);
    await tester.pumpAndSettle();
    expect(chart(tester).xAxis, 'loss');
    expect(find.text('X: loss'), findsOneWidget);
    expect(repository.histories.length, 50);
    expect(repository.histories.last.xKey, 'loss');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
