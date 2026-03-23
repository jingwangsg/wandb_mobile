import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/wandb_line_chart.dart';
import 'package:wandb_mobile/features/charts/providers/chart_preferences_providers.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/presentation/widgets/system_metrics_panel.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

import '../../../../test_support/in_memory_run_chart_preferences_store.dart';

class SystemRunsRepository extends RunsRepository {
  SystemRunsRepository(this.rows) : super(GraphqlClient(apiKey: 'test'));

  final List<Map<String, dynamic>> rows;

  @override
  Future<List<Map<String, dynamic>>> getSystemMetrics({
    required String entity,
    required String project,
    required String runName,
    int samples = 500,
  }) async {
    return rows;
  }
}

Widget _buildSystemPanel(SystemRunsRepository repository) {
  return ProviderScope(
    overrides: [
      runsRepositoryProvider.overrideWithValue(repository),
      runChartPreferencesStoreProvider.overrideWithValue(
        InMemoryRunChartPreferencesStore(),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 700,
          height: 1000,
          child: SystemMetricsPanel(
            entity: 'nv-gear',
            project: 'n1d6_ttt_fm_assembly',
            runName: 'b2sl4gke',
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders grouped system metrics from event rows', (tester) async {
    final repository = SystemRunsRepository([
      {
        '_timestamp': 1700000000,
        'system': {
          'gpu': {'utilization': 0.5, 'memory': 0.25},
          'cpu': 0.8,
        },
      },
      {
        '_timestamp': 1700000060,
        'system': {
          'gpu': {'utilization': 0.6, 'memory': 0.35},
          'cpu': 0.7,
        },
      },
    ]);

    await tester.pumpWidget(_buildSystemPanel(repository));
    await tester.pumpAndSettle();

    expect(find.text('system'), findsWidgets);
    expect(find.text('gpu'), findsWidgets);
    expect(find.text('utilization'), findsOneWidget);
    expect(find.byType(WandbLineChart), findsAtLeastNWidgets(2));
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty state when no numeric system metrics exist', (
    tester,
  ) async {
    final repository = SystemRunsRepository([
      {'_timestamp': 1700000000, 'state': 'heartbeat'},
    ]);

    await tester.pumpWidget(_buildSystemPanel(repository));
    await tester.pumpAndSettle();

    expect(find.text('No system metrics logged'), findsOneWidget);
  });
}
