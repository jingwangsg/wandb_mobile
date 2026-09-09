import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/core/providers/mobile_preferences.dart';
import 'package:wandb_mobile/features/charts/providers/panel_providers.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/presentation/recent_runs_screen.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

import 'test_support/mobile_test_support.dart';

class _StreamRepository extends RunsRepository {
  _StreamRepository() : super(GraphqlClient(apiKey: 'fixture'));
  final requestedMetrics = <String>[];

  @override
  Future<Map<String, dynamic>> getProjectMetrics({
    required String entity,
    required String project,
  }) async => {
    'keys': {
      for (final key in [
        '_step',
        'system/gpu.0.gpu',
        'system.cpu',
        'train/loss',
        'ecosystem/accuracy',
      ])
        key: {},
    },
  };

  @override
  Future<List<MetricSeries>> getSampledHistory({
    required String entity,
    required String project,
    required String runName,
    required List<String> keys,
    int samples = 500,
  }) async {
    requestedMetrics.addAll(keys);
    return [
      for (final key in keys)
        MetricSeries(
          key: key,
          points: const [MetricPoint(step: 1, value: 0.1)],
        ),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getSystemMetrics({
    required String entity,
    required String project,
    required String runName,
    int samples = 500,
  }) async => [
    {'system.cpu': 42},
    {
      'system': {'cpu': 43},
    },
    {'system/cpu': 44},
  ];
}

void main() {
  const project = ProjectRef(entity: 'team', project: 'project');

  test(
    'project catalog separates both system namespaces without removing custom metrics',
    () async {
      final container = ProviderContainer(
        overrides: [
          runsRepositoryProvider.overrideWithValue(_StreamRepository()),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(projectMetricKeysProvider(project).future), [
        'ecosystem/accuracy',
        'train/loss',
      ]);
    },
  );

  for (final metric in ['train/loss', 'ecosystem/accuracy']) {
    testWidgets(
      'starred system metrics cannot replace $metric in a run preview',
      (tester) async {
        final repository = _StreamRepository();
        final container = ProviderContainer(
          overrides: [
            ...mobileTestOverrides(),
            runsRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        final preferences = container.read(mobilePreferencesProvider.notifier);
        await preferences.toggleMetric(project.path, 'system/gpu.0.gpu');
        await preferences.toggleMetric(project.path, 'system.cpu');
        await preferences.toggleMetric(project.path, 'system/memory');
        final run = WandbRun(
          id: 'run-id',
          name: 'run',
          displayName: 'Example run',
          state: RunState.finished,
          historyKeys: {
            'keys': {
              for (final key in ['system/gpu.0.gpu', 'system.cpu', metric])
                key: {
                  'typeCounts': [
                    {'type': 'number', 'count': 1000},
                  ],
                },
            },
          },
          summaryMetrics: {metric: 0.1, 'system/memory': 90},
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(body: RunCard(run: run, project: project)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(repository.requestedMetrics, [metric]);
        expect(find.text(metric), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'flat dotted, nested, and slash event keys retain one system series',
    () async {
      final container = ProviderContainer(
        overrides: [
          runsRepositoryProvider.overrideWithValue(_StreamRepository()),
        ],
      );
      addTearDown(container.dispose);
      final series = await container.read(
        runSystemSeriesProvider(
          const RunRef(entity: 'team', project: 'project', runName: 'run'),
        ).future,
      );
      expect(series, hasLength(1));
      expect(series.single.key, 'system/cpu');
      expect(series.single.points.map((point) => point.value), [42, 43, 44]);
    },
  );
}
