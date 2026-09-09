import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/api_exceptions.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/providers/api_client_provider.dart';
import 'package:wandb_mobile/features/auth/providers/auth_providers.dart';

import 'test_support/mobile_test_support.dart';

class OfflineViewerClient extends GraphqlClient {
  OfflineViewerClient() : super(apiKey: 'test');

  @override
  Future<Map<String, dynamic>> query(
    String queryString, {
    Map<String, dynamic>? variables,
  }) async {
    if (!queryString.contains('GetViewer'))
      throw StateError('Unexpected query: $queryString');
    throw const NetworkException();
  }
}

void main() {
  for (final offline in [false, true]) {
    test(
      'auto-login ${offline ? 'network failure preserves' : 'rejected credentials revoke'} the stored push identity',
      () async {
        final storage =
            MemorySecureStorage()
              ..apiKey = 'stored-key'
              ..userId = 'alice'
              ..pushEnabled = true;
        final container = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            graphqlClientFactoryProvider.overrideWithValue(
              ({required apiKey, required baseUrl}) =>
                  offline ? OfflineViewerClient() : ViewerClient(viewer: null),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(authProvider);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(authProvider).status, AuthStatus.unauthenticated);
        expect(await storage.getUserId(), offline ? 'alice' : isNull);
        expect(await storage.getPushEnabled(userId: 'alice'), offline);
        expect(await storage.getApiKey(), offline ? 'stored-key' : isNull);
      },
    );
  }
}
