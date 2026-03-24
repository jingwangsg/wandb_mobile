import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/presentation/runs_list_screen.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

class StaticRunsRepository extends RunsRepository {
  StaticRunsRepository() : super(GraphqlClient(apiKey: 'test'));

  @override
  Future<PaginatedResult<WandbRun>> getRuns({
    required String entity,
    required String project,
    String? cursor,
    int perPage = 20,
    String? order,
    Map<String, dynamic>? filters,
  }) async {
    return const PaginatedResult(
      items: [
        WandbRun(
          id: 'run-1',
          name: 'run-1',
          displayName: 'Example Run',
          state: RunState.running,
        ),
      ],
    );
  }
}

void main() {
  testWidgets('shows search chip and advanced filter summary', (tester) async {
    final container = ProviderContainer(
      overrides: [
        runsRepositoryProvider.overrideWithValue(StaticRunsRepository()),
      ],
    );
    addTearDown(container.dispose);

    const projectRef = ProjectRef(entity: 'entity', project: 'project');
    final notifier = container.read(runFiltersProvider(projectRef).notifier);
    notifier.setSearchQuery('demo');
    notifier.applyAdvancedFilter(
      const RunFilterGroup(
        logic: RunFilterLogic.and,
        children: [
          RunFilterCondition(
            fieldPath: 'state',
            operator: RunFilterOperator.eq,
            valueType: RunFilterValueType.text,
            rawValue: 'running',
          ),
          RunFilterCondition(
            fieldPath: 'group',
            operator: RunFilterOperator.eq,
            valueType: RunFilterValueType.text,
            rawValue: 'exp-a',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: RunsListScreen(entity: 'entity', project: 'project'),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Search: demo'), findsOneWidget);
    expect(find.text('2 filters'), findsOneWidget);

    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isTrue);
    expect((badge.label as Text).data, '2');
  });
}
