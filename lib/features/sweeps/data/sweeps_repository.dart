import '../../../core/api/graphql_client.dart';
import '../../../core/api/graphql_queries.dart';
import '../../../core/models/paginated.dart';
import '../../../core/models/sweep.dart';

class SweepsRepository {
  const SweepsRepository(this._client);
  final GraphqlClient _client;

  Future<PaginatedResult<WandbSweep>> getSweeps({
    required String entity,
    required String project,
    String? cursor,
    int perPage = 50,
  }) async {
    final data = await _client.query(
      WandbQueries.getSweeps,
      variables: {
        'entity': entity,
        'project': project,
        'cursor': cursor,
        'perPage': perPage,
      },
    );

    final proj = data['project'] as Map<String, dynamic>;
    final sweepsData = proj['sweeps'] as Map<String, dynamic>;
    final pageInfo = sweepsData['pageInfo'] as Map<String, dynamic>;
    final edges = sweepsData['edges'] as List;
    final totalCount = proj['totalSweeps'] as int?;

    return PaginatedResult(
      items: edges
          .map((e) =>
              WandbSweep.fromJson(e['node'] as Map<String, dynamic>))
          .toList(),
      endCursor: pageInfo['endCursor'] as String?,
      hasNextPage: pageInfo['hasNextPage'] as bool? ?? false,
      totalCount: totalCount,
    );
  }
}
