import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/core/models/run_file.dart';
import 'package:wandb_mobile/features/charts/providers/chart_preferences_providers.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/presentation/run_detail_screen.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

import '../../../test_support/in_memory_run_chart_preferences_store.dart';

class RunDetailRepository extends RunsRepository {
  RunDetailRepository() : super(GraphqlClient(apiKey: 'test'));

  @override
  Future<List<MetricSeries>> getSampledHistory({
    required String entity,
    required String project,
    required String runName,
    required List<String> keys,
    int samples = 500,
  }) async {
    return keys
        .map(
          (key) => MetricSeries(
            key: key,
            points: const [
              MetricPoint(step: 1, value: 0.5),
              MetricPoint(step: 2, value: 0.25),
            ],
          ),
        )
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getSystemMetrics({
    required String entity,
    required String project,
    required String runName,
    int samples = 500,
  }) async {
    return [
      {
        '_timestamp': 1700000000,
        'system': {
          'gpu': {'utilization': 0.5},
        },
      },
    ];
  }

  @override
  Future<PaginatedResult<RunFile>> getRunFiles({
    required String entity,
    required String project,
    required String runName,
    String? cursor,
    int limit = 50,
    List<String>? fileNames,
  }) async {
    return const PaginatedResult(
      items: [
        RunFile(
          id: 'file-1',
          name: 'output.log',
          directUrl: 'https://example.com/output.log',
        ),
      ],
      totalCount: 1,
    );
  }
}

const _run = WandbRun(
  id: 'run-id',
  name: 'b2sl4gke',
  displayName: 'example',
  state: RunState.crashed,
  historyKeys: {
    'keys': {
      'train/train/loss': {
        'typeCounts': [
          {'type': 'number', 'count': 10},
        ],
      },
    },
  },
  config: {
    'payload': {'value': '{"foo":1}'},
  },
  summaryMetrics: {'train/train/loss': 0.5},
);

void main() {
  testWidgets('shows metrics, system, and files tabs in wide layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runsRepositoryProvider.overrideWithValue(RunDetailRepository()),
          runChartPreferencesStoreProvider.overrideWithValue(
            InMemoryRunChartPreferencesStore(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: RunDetailScreen(
                entity: 'nv-gear',
                project: 'n1d6_ttt_fm_assembly',
                runName: 'b2sl4gke',
                run: _run,
                embedded: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Metrics'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('Run Files'), findsOneWidget);
    expect(find.text('output.log'), findsOneWidget);
  });
}
