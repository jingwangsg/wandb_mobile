import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/graphql_client.dart';
import '../../features/auth/data/secure_storage_service.dart';

/// Provides the GraphQL client singleton. Depends on stored API key.
final apiClientProvider = Provider<GraphqlClient?>((ref) {
  // This will be overridden when auth state changes.
  // See auth_providers.dart for the actual initialization.
  return null;
});

/// Provides the secure storage service.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
