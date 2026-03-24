import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/models/sweep.dart';
import 'package:wandb_mobile/features/sweeps/data/sweeps_repository.dart';
import 'package:wandb_mobile/features/sweeps/providers/sweeps_providers.dart';

class RecordingSweepsRepository extends SweepsRepository {
  RecordingSweepsRepository() : super(GraphqlClient(apiKey: 'test'));

  String? lastEntity;
  String? lastProject;

  @override
  Future<PaginatedResult<WandbSweep>> getSweeps({
    required String entity,
    required String project,
    String? cursor,
    int perPage = 20,
  }) async {
    lastEntity = entity;
    lastProject = project;
    return const PaginatedResult(items: []);
  }
}

void main() {
  test('sweepsProvider passes typed project ref to repository', () async {
    final repository = RecordingSweepsRepository();
    final container = ProviderContainer(
      overrides: [sweepsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    const projectRef = ProjectRef(entity: 'entity', project: 'project');
    await container.read(sweepsProvider(projectRef).future);

    expect(repository.lastEntity, 'entity');
    expect(repository.lastProject, 'project');
  });
}
