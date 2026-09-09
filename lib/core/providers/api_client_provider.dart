import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/secure_storage_service.dart';
import '../api/graphql_client.dart';

/// Provides the secure storage service.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final graphqlClientFactoryProvider = Provider<
  GraphqlClient Function({required String apiKey, required String baseUrl})
>(
  (ref) =>
      ({required apiKey, required baseUrl}) =>
          GraphqlClient(apiKey: apiKey, baseUrl: baseUrl),
);
