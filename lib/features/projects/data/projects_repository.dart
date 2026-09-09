import '../../../core/api/graphql_client.dart';
import '../../../core/api/graphql_queries.dart';
import '../../../core/api/mobile_queries.dart';
import '../../../core/models/paginated.dart';
import '../../../core/models/project.dart';

class ProjectsRepository {
  const ProjectsRepository(this._client);
  final GraphqlClient _client;

  Future<PaginatedResult<WandbProject>> searchProjects({
    required String entity,
    String? pattern,
    String? cursor,
  }) async {
    final data = await _client.query(
      MobileQueries.searchProjects,
      variables: {'entity': entity, 'pattern': pattern, 'cursor': cursor},
    );
    final projects = data['projects'] as Map<String, dynamic>;
    return PaginatedResult(
      items:
          (projects['edges'] as List)
              .map(
                (edge) =>
                    WandbProject.fromJson(edge['node'] as Map<String, dynamic>),
              )
              .toList(),
      endCursor: projects['pageInfo']['endCursor'] as String?,
      hasNextPage: projects['pageInfo']['hasNextPage'] as bool,
    );
  }

  Future<void> setStarred(WandbProject project, bool starred) async {
    await _client.query(
      starred ? MobileQueries.starProject : MobileQueries.unstarProject,
      variables: {'entity': project.entityName, 'project': project.name},
    );
  }

  Future<PaginatedResult<WandbProject>> getStarredProjects({
    String? cursor,
  }) async {
    final data = await _client.query(
      r'''
      query MobileStarredProjects($cursor: String) {
        viewer { starredProjects(first: 50, after: $cursor) {
          edges { node { id name entityName description createdAt lastActive starred runCount } }
          pageInfo { endCursor hasNextPage }
        } }
      }
    ''',
      variables: {'cursor': cursor},
    );
    final projects = data['viewer']['starredProjects'] as Map;
    return PaginatedResult(
      items:
          (projects['edges'] as List)
              .map(
                (edge) =>
                    WandbProject.fromJson(edge['node'] as Map<String, dynamic>),
              )
              .toList(),
      endCursor: projects['pageInfo']['endCursor'] as String?,
      hasNextPage: projects['pageInfo']['hasNextPage'] as bool,
    );
  }

  Future<PaginatedResult<WandbProject>> getProjects({
    required String entity,
    String? cursor,
    int perPage = 50,
  }) async {
    final data = await _client.query(
      WandbQueries.getProjects,
      variables: {'entity': entity, 'cursor': cursor, 'perPage': perPage},
    );

    final models = data['models'] as Map<String, dynamic>;
    final pageInfo = models['pageInfo'] as Map<String, dynamic>;
    final edges = models['edges'] as List;

    return PaginatedResult(
      items:
          edges
              .map(
                (e) => WandbProject.fromJson(e['node'] as Map<String, dynamic>),
              )
              .toList(),
      endCursor: pageInfo['endCursor'] as String?,
      hasNextPage: pageInfo['hasNextPage'] as bool? ?? false,
    );
  }
}
