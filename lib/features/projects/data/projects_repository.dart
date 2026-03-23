import '../../../core/api/graphql_client.dart';
import '../../../core/api/graphql_queries.dart';
import '../../../core/models/paginated.dart';
import '../../../core/models/project.dart';

class ProjectsRepository {
  const ProjectsRepository(this._client);
  final GraphqlClient _client;

  Future<PaginatedResult<WandbProject>> getProjects({
    required String entity,
    String? cursor,
    int perPage = 50,
  }) async {
    final data = await _client.query(
      WandbQueries.getProjects,
      variables: {
        'entity': entity,
        'cursor': cursor,
        'perPage': perPage,
      },
    );

    final models = data['models'] as Map<String, dynamic>;
    final pageInfo = models['pageInfo'] as Map<String, dynamic>;
    final edges = models['edges'] as List;

    return PaginatedResult(
      items: edges
          .map((e) =>
              WandbProject.fromJson(e['node'] as Map<String, dynamic>))
          .toList(),
      endCursor: pageInfo['endCursor'] as String?,
      hasNextPage: pageInfo['hasNextPage'] as bool? ?? false,
    );
  }
}
