import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/models/run.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

class RecordingRunsRepository extends RunsRepository {
  RecordingRunsRepository() : super(GraphqlClient(apiKey: 'test'));

  Map<String, dynamic>? lastFilters;
  String? lastOrder;

  @override
  Future<PaginatedResult<WandbRun>> getRuns({
    required String entity,
    required String project,
    String? cursor,
    int perPage = 20,
    String? order,
    Map<String, dynamic>? filters,
  }) async {
    lastOrder = order;
    lastFilters = filters;
    return const PaginatedResult(items: []);
  }
}

void main() {
  test('runsProvider sends merged search and advanced filters', () async {
    final repository = RecordingRunsRepository();
    final container = ProviderContainer(
      overrides: [runsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    const projectRef = ProjectRef(entity: 'entity', project: 'project');
    final notifier = container.read(runFiltersProvider(projectRef).notifier);
    notifier.setOrder('-heartbeat_at');
    notifier.setSearchQuery('baseline');
    notifier.applyAdvancedFilter(
      const RunFilterGroup(
        logic: RunFilterLogic.or,
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

    final sub = container.listen(runsProvider(projectRef), (_, __) {});
    addTearDown(sub.close);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(repository.lastOrder, '-heartbeat_at');
    expect(repository.lastFilters, {
      r'$and': [
        {
          'displayName': {r'$regex': 'baseline'},
        },
        {
          r'$or': [
            {'state': 'running'},
            {'group': 'exp-a'},
          ],
        },
      ],
    });
  });

  test('ProjectRef.fromPath parses valid project path', () {
    final ref = ProjectRef.fromPath('entity/project');

    expect(ref.entity, 'entity');
    expect(ref.project, 'project');
    expect(ref.path, 'entity/project');
  });

  test('ProjectRef.fromPath rejects invalid project path', () {
    expect(() => ProjectRef.fromPath('entity'), throwsArgumentError);
    expect(
      () => ProjectRef.fromPath('entity/project/extra'),
      throwsArgumentError,
    );
  });
}
