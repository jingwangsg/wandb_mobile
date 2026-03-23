import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paginated.dart';
import '../../../core/models/project.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/projects_repository.dart';

final projectsRepositoryProvider = Provider<ProjectsRepository>((ref) {
  final client = ref.watch(graphqlClientProvider);
  return ProjectsRepository(client);
});

/// Paginated project list for the current entity.
class ProjectsNotifier
    extends StateNotifier<AsyncValue<PaginatedResult<WandbProject>>> {
  ProjectsNotifier(this._repo, this._entity)
      : super(const AsyncValue.loading()) {
    load();
  }

  final ProjectsRepository _repo;
  final String _entity;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final result = await _repo.getProjects(entity: _entity);
      state = AsyncValue.data(result);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasNextPage) return;

    try {
      final next = await _repo.getProjects(
        entity: _entity,
        cursor: current.endCursor,
      );
      state = AsyncValue.data(current.appendPage(next));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => load();
}

final projectsProvider = StateNotifierProvider.family<ProjectsNotifier,
    AsyncValue<PaginatedResult<WandbProject>>, String>(
  (ref, entity) {
    final repo = ref.watch(projectsRepositoryProvider);
    return ProjectsNotifier(repo, entity);
  },
);
