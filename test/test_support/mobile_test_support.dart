import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/providers/api_client_provider.dart';
import 'package:wandb_mobile/core/providers/mobile_preferences.dart';
import 'package:wandb_mobile/features/auth/data/secure_storage_service.dart';

class MemoryMobilePreferencesStore extends MobilePreferencesStore {
  final values = <String, MobilePreferences>{};
  @override
  MobilePreferences read(String account) =>
      values[account] ?? const MobilePreferences();
  @override
  Future<void> write(String account, MobilePreferences preferences) async {
    values[account] = preferences;
  }
}

class MemorySecureStorage extends SecureStorageService {
  String? apiKey;
  String? entity;
  String? baseUrl;
  String? userId;
  final pushByUser = <String?, bool>{};
  bool get pushEnabled => pushByUser[userId] ?? false;
  set pushEnabled(bool value) => pushByUser[userId] = value;
  @override
  Future<String?> getApiKey() async => apiKey;
  @override
  Future<void> setApiKey(String key) async {
    apiKey = key;
  }

  @override
  Future<void> deleteApiKey() async {
    apiKey = null;
  }

  @override
  Future<String?> getEntity() async => entity;
  @override
  Future<void> setEntity(String entity) async {
    this.entity = entity;
  }

  @override
  Future<String?> getBaseUrl() async => baseUrl;
  @override
  Future<void> setBaseUrl(String url) async {
    baseUrl = url;
  }

  @override
  Future<void> deleteBaseUrl() async {
    baseUrl = null;
  }

  @override
  Future<String?> getUserId() async => userId;
  @override
  Future<void> setUserId(String id) async {
    userId = id;
  }

  @override
  Future<bool> getPushEnabled({String? userId}) async =>
      pushByUser[userId ?? this.userId] ?? false;
  @override
  Future<void> setPushEnabled(bool value, {String? userId}) async {
    pushByUser[userId ?? this.userId] = value;
  }

  @override
  Future<void> clearAll() async {
    apiKey = null;
    entity = null;
    baseUrl = null;
    userId = null;
    pushByUser.clear();
  }
}

class ViewerClient extends GraphqlClient {
  ViewerClient({
    this.viewer = const {
      'id': 'user-1',
      'username': 'alice',
      'entity': 'alice',
      'teams': {
        'edges': [
          {
            'node': {'name': 'nv-gear'},
          },
        ],
      },
    },
  }) : super(apiKey: 'test-key');
  final Map<String, dynamic>? viewer;
  @override
  Future<Map<String, dynamic>> query(
    String queryString, {
    Map<String, dynamic>? variables,
  }) async {
    if (!queryString.contains('GetViewer'))
      throw StateError('Unexpected query: $queryString');
    return {'viewer': viewer};
  }
}

List<Override> mobileTestOverrides() => [
  secureStorageProvider.overrideWithValue(MemorySecureStorage()),
  mobilePreferencesStoreProvider.overrideWithValue(
    MemoryMobilePreferencesStore(),
  ),
  graphqlClientFactoryProvider.overrideWithValue(
    ({required apiKey, required baseUrl}) => ViewerClient(),
  ),
];
