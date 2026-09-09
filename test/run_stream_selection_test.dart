import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/features/charts/presentation/panels_view.dart';
import 'package:wandb_mobile/features/charts/providers/panel_providers.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';
import 'package:wandb_mobile/features/runs/utils/metric_selection.dart';

import 'test_support/mobile_test_support.dart';

class StreamRepository extends RunsRepository {
  StreamRepository() : super(GraphqlClient(apiKey: 'fixture'));
  final requestedMetrics = <String>[];
  @override
  Future<List<MetricSeries>> getSampledHistory({
    required String entity,
    required String project,
    required String runName,
    required List<String> keys,
    int samples = 500,
  }) async {
    requestedMetrics.addAll(keys);
    return keys
        .map(
          (key) => MetricSeries(
            key: key,
            points:
                key.startsWith('system/')
                    ? []
                    : const [
                      MetricPoint(step: 32, value: 0.094),
                      MetricPoint(step: 10000, value: 0.091),
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
  }) async => [
    {'_timestamp': 1700000000, 'system.cpu': 42, 'system.gpu.0.gpu': 90},
  ];
}

void main() {
  testWidgets(
    'mixed W&B historyKeys route system keys to events and show loss first',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = StreamRepository();
      final run = WandbRun(
        id: 'id',
        name: 'rz2hg2jr',
        displayName: 'n2turbo_v2_tm6to27_200k',
        state: RunState.running,
        historyKeys: {
          'keys': {
            for (var index = 0; index < 60; index++)
              'system/gpu.$index.gpu': {
                'typeCounts': [
                  {'type': 'number', 'count': 3600},
                ],
              },
            'system/cpu': {
              'typeCounts': [
                {'type': 'number', 'count': 3600},
              ],
            },
            'train/batch/reward_count': {
              'typeCounts': [
                {'type': 'number', 'count': 5000},
              ],
            },
            'train/loss': {
              'typeCounts': [
                {'type': 'number', 'count': 5299},
              ],
            },
          },
        },
        summaryMetrics: const {'train/loss': 0.092},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...mobileTestOverrides(),
            runsRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PanelsView(
                project: const ProjectRef(
                  entity: 'nv-gear',
                  project: 'gr00t2_pretrain',
                ),
                run: run,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        repo.requestedMetrics.any((key) => key.startsWith('system/')),
        false,
      );
      expect(find.text('train/loss').hitTestable(), findsOneWidget);
      expect(find.text('system'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'flat dotted event keys have the same names as system history metadata',
    () async {
      final container = ProviderContainer(
        overrides: [
          runsRepositoryProvider.overrideWithValue(StreamRepository()),
        ],
      );
      addTearDown(container.dispose);
      final series = await container.read(
        runSystemSeriesProvider(
          const RunRef(
            entity: 'nv-gear',
            project: 'gr00t2_pretrain',
            runName: 'rz2hg2jr',
          ),
        ).future,
      );
      expect(
        series.map((line) => line.key),
        containsAll(['system/cpu', 'system/gpu.0.gpu']),
      );
      expect(
        series
            .firstWhere((line) => line.key == 'system/cpu')
            .points
            .single
            .value,
        42,
      );
    },
  );

  test(
    'frequent epoch logging cannot outrank the loss metric for a run preview',
    () {
      final selected = defaultMetricKeys(
        ['train/epoch', 'train/loss'],
        {
          'train/epoch': {
            'typeCounts': [
              {'type': 'number', 'count': 10000000},
            ],
          },
          'train/loss': {
            'typeCounts': [
              {'type': 'number', 'count': 5000},
            ],
          },
        },
      );
      expect(selected.first, 'train/loss');
    },
  );
}
