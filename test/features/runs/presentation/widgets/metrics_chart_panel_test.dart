import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/diagnostics/runtime_diagnostics.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/presentation/widgets/metrics_chart_panel.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

class RecordingRunsRepository extends RunsRepository {
  RecordingRunsRepository({this.error, this.pointCount = 2})
    : super(GraphqlClient(apiKey: 'test'));

  List<String>? requestedKeys;
  final Object? error;
  final int pointCount;

  @override
  Future<List<MetricSeries>> getSampledHistory({
    required String entity,
    required String project,
    required String runName,
    required List<String> keys,
    int samples = 500,
  }) async {
    requestedKeys = [...keys];
    if (error != null) throw error!;
    return keys
        .map(
          (key) => MetricSeries(
            key: key,
            points: List.generate(
              pointCount,
              (index) => MetricPoint(
                step: index + 1,
                value: (index % 37).toDouble() / 37,
              ),
            ),
          ),
        )
        .toList();
  }
}

const _trainMetricsRun = WandbRun(
  id: 'run-id',
  name: 'b2sl4gke',
  displayName: 'example',
  state: RunState.crashed,
  historyKeys: {
    'keys': {
      'slowest_rank/model_forward_rank': {
        'typeCounts': [
          {'type': 'number', 'count': 133},
        ],
      },
      'slowest_rank/model_forward_score': {
        'typeCounts': [
          {'type': 'number', 'count': 133},
        ],
      },
      'train/epoch': {
        'typeCounts': [
          {'type': 'number', 'count': 49140},
        ],
      },
      'train/global_step': {
        'typeCounts': [
          {'type': 'number', 'count': 49273},
        ],
      },
      'train/loss': {
        'typeCounts': [
          {'type': 'number', 'count': 1198},
        ],
      },
      'train/train/flow_matching_loss': {
        'typeCounts': [
          {'type': 'number', 'count': 11986},
        ],
      },
      'train/train/future_latent_loss': {
        'typeCounts': [
          {'type': 'number', 'count': 11986},
        ],
      },
      'train/train/loss': {
        'typeCounts': [
          {'type': 'number', 'count': 11986},
        ],
      },
    },
  },
);

Widget _buildMetricsPanel({
  required RecordingRunsRepository repository,
  required WandbRun run,
  required double width,
}) {
  return ProviderScope(
    overrides: [runsRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 600,
          child: MetricsChartPanel(
            entity: 'nv-gear',
            project: 'n1d6_ttt_fm_assembly',
            runName: run.name,
            run: run,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    RuntimeDiagnostics.instance.entries.value = const [];
  });

  testWidgets('prefers train metrics for the initial chart selection', (
    tester,
  ) async {
    final repository = RecordingRunsRepository();

    await tester.pumpWidget(
      _buildMetricsPanel(
        repository: repository,
        run: _trainMetricsRun,
        width: 700,
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedKeys, [
      'train/train/flow_matching_loss',
      'train/train/future_latent_loss',
      'train/train/loss',
    ]);
  });

  testWidgets('shows request diagnostics when loading metrics fails', (
    tester,
  ) async {
    final repository = RecordingRunsRepository(error: ArgumentError.value(500));
    const run = WandbRun(
      id: 'run-id',
      name: 'b13zjcaq',
      displayName: 'example',
      state: RunState.crashed,
      historyKeys: {
        'keys': {
          'system/network.recv': {
            'typeCounts': [
              {'type': 'number', 'count': 4},
            ],
          },
        },
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [runsRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 600,
              child: MetricsChartPanel(
                entity: 'nv-gear',
                project: 'n1d6_ttt_fm_assembly',
                runName: run.name,
                run: run,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Failed to load metrics'), findsOneWidget);
    expect(find.text('Request Parameters'), findsOneWidget);
    expect(find.textContaining('n1d6_ttt_fm_assembly'), findsWidgets);
    expect(find.textContaining('system/network.recv'), findsWidgets);
    expect(find.textContaining('Invalid argument'), findsWidgets);
  });

  testWidgets(
    'renders 500 sampled points without build errors in wide layout',
    (tester) async {
      final repository = RecordingRunsRepository(pointCount: 500);

      await tester.pumpWidget(
        _buildMetricsPanel(
          repository: repository,
          run: _trainMetricsRun,
          width: 700,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Failed to load metrics'), findsNothing);
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'renders 500 sampled points in narrow layout and remains stable after smoothing changes',
    (tester) async {
      final repository = RecordingRunsRepository(pointCount: 500);

      await tester.pumpWidget(
        _buildMetricsPanel(
          repository: repository,
          run: _trainMetricsRun,
          width: 360,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Failed to load metrics'), findsNothing);
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('groups metrics by slash prefixes in wide layout', (
    tester,
  ) async {
    final repository = RecordingRunsRepository();

    await tester.pumpWidget(
      _buildMetricsPanel(
        repository: repository,
        run: _trainMetricsRun,
        width: 700,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('train'), findsWidgets);
    expect(find.text('flow_matching_loss'), findsOneWidget);
    expect(find.text('future_latent_loss'), findsOneWidget);
  });

  testWidgets('opens grouped selector sheet in narrow layout', (tester) async {
    final repository = RecordingRunsRepository();

    await tester.pumpWidget(
      _buildMetricsPanel(
        repository: repository,
        run: _trainMetricsRun,
        width: 360,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Metrics ('));
    await tester.pumpAndSettle();

    expect(find.text('Select Metrics'), findsOneWidget);
    expect(find.text('train'), findsWidgets);
    expect(find.text('flow_matching_loss'), findsOneWidget);
  });
}
