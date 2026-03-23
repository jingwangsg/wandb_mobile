import '../../../core/api/graphql_client.dart';
import '../../../core/api/graphql_queries.dart';
import '../../../core/models/user.dart';

class AuthRepository {
  const AuthRepository(this._client);
  final GraphqlClient _client;

  /// Validate API key by calling GetViewer.
  /// Returns the authenticated user on success, throws on failure.
  Future<WandbUser> validateApiKey() async {
    final data = await _client.query(WandbQueries.getViewer);
    final viewer = data['viewer'] as Map<String, dynamic>;
    return WandbUser.fromJson(viewer);
  }
}
