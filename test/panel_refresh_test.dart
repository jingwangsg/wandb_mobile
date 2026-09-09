import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/features/charts/presentation/panels_view.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/wandb_line_chart.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

import 'test_support/mobile_test_support.dart';

class SlowProjectRepository extends RunsRepository {
  SlowProjectRepository() : super(GraphqlClient(apiKey: 'fixture'));
  final ready = Completer<void>();
  int runPages = 0;
  int histories = 0;
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
    runPages++;
    return PaginatedResult(
      items: [
        for (var index = 0; index < 100; index++)
          WandbRun(
            id: '$index',
            name: 'run-$index',
            displayName: 'Run $index',
            state: RunState.finished,
          ),
      ],
    );
  }

  @override
  Future<List<MetricSeries>> getSampledHistory({
    required String entity,
    required String project,
    required String runName,
    required List<String> keys,
    int samples = 500,
  }) async {
    histories++;
    await ready.future;
    return [
      MetricSeries(
        key: keys.single,
        points: const [
          MetricPoint(step: 0, value: 1),
          MetricPoint(step: 1, value: 0.5),
        ],
      ),
    ];
  }
}

void main() {
  testWidgets('a project chart load survives the 30-second refresh interval', (
    tester,
  ) async {
    final oldLifecycle = tester.binding.lifecycleState;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() {
      if (oldLifecycle != null)
        tester.binding.handleAppLifecycleStateChanged(oldLifecycle);
    });
    final repository = SlowProjectRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...mobileTestOverrides(),
          runsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PanelsView(
              project: ProjectRef(entity: 'team', project: 'large'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repository.runPages, 1);
    expect(repository.histories, 6);
    await tester.pump(const Duration(seconds: 31));
    expect(
      repository.runPages,
      1,
      reason: 'the active generation must not be cancelled by polling',
    );
    repository.ready.complete();
    await tester.pumpAndSettle();
    final chart = tester.widget<WandbLineChart>(find.byType(WandbLineChart));
    expect(chart.series.length, 100);
    expect(repository.histories, 100);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
