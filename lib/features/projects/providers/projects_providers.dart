import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paginated.dart';
import '../../../core/models/project.dart';
import '../../../core/providers/paginated_async_notifier.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/projects_repository.dart';

final projectsRepositoryProvider = Provider<ProjectsRepository>((ref) {
  final client = ref.watch(graphqlClientProvider);
  return ProjectsRepository(client);
});

/// Paginated project list for the current entity.
class ProjectsNotifier extends PaginatedAsyncNotifier<WandbProject> {
  ProjectsNotifier(this._repo, this._entity) : super() {
    load();
  }

  final ProjectsRepository _repo;
  final String _entity;

  @override
  Future<PaginatedResult<WandbProject>> loadPage({String? cursor}) {
    return _repo.getProjects(entity: _entity, cursor: cursor);
  }
}

final projectsProvider = StateNotifierProvider.family<
  ProjectsNotifier,
  AsyncValue<PaginatedResult<WandbProject>>,
  String
>((ref, entity) {
  final repo = ref.watch(projectsRepositoryProvider);
  return ProjectsNotifier(repo, entity);
});

class ProjectSearchNotifier extends PaginatedAsyncNotifier<WandbProject> {
  ProjectSearchNotifier(this._repo, this._entity, this._query) {
    load();
  }
  final ProjectsRepository _repo;
  final String _entity;
  final String _query;

  @override
  Future<PaginatedResult<WandbProject>> loadPage({String? cursor}) =>
      _repo.searchProjects(entity: _entity, pattern: _query, cursor: cursor);
}

final projectSearchProvider = StateNotifierProvider.autoDispose.family<
  ProjectSearchNotifier,
  AsyncValue<PaginatedResult<WandbProject>>,
  ({String entity, String query})
>(
  (ref, value) => ProjectSearchNotifier(
    ref.watch(projectsRepositoryProvider),
    value.entity,
    value.query,
  ),
);

class StarredProjectsNotifier extends PaginatedAsyncNotifier<WandbProject> {
  StarredProjectsNotifier(this._repo) {
    load();
  }
  final ProjectsRepository _repo;
  @override
  Future<PaginatedResult<WandbProject>> loadPage({String? cursor}) =>
      _repo.getStarredProjects(cursor: cursor);
}

final starredProjectsProvider = StateNotifierProvider.autoDispose<
  StarredProjectsNotifier,
  AsyncValue<PaginatedResult<WandbProject>>
>((ref) => StarredProjectsNotifier(ref.watch(projectsRepositoryProvider)));
