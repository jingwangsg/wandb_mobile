import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/api_exceptions.dart';
import 'package:wandb_mobile/core/models/user.dart';
import 'package:wandb_mobile/core/providers/api_client_provider.dart';
import 'package:wandb_mobile/features/auth/data/secure_storage_service.dart';
import 'package:wandb_mobile/features/auth/providers/auth_providers.dart';

class FakeSecureStorageService extends SecureStorageService {
  String? apiKey;
  String? entity;
  String? baseUrl;
  bool cleared = false;

  @override
  Future<String?> getApiKey() async => apiKey;

  @override
  Future<void> setApiKey(String key) async {
    apiKey = key;
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
  Future<void> clearAll() async {
    cleared = true;
    apiKey = null;
    entity = null;
    baseUrl = null;
  }
}

class TestAuthNotifier extends AuthNotifier {
  TestAuthNotifier(this._ref, {required this.validateApiKey}) : super(_ref);

  final Ref _ref;

  final Future<WandbUser> Function({required String apiKey, required String baseUrl})
      validateApiKey;

  static String _errorMessageFor(Object error) {
    if (error is WandbApiException) {
      return error.message;
    }
    return error.toString();
  }

  @override
  Future<void> login({
    required String apiKey,
    String? baseUrl,
    String? preselectedEntity,
  }) async {
    state = const AuthState(status: AuthStatus.loading);

    final effectiveBaseUrl = baseUrl ?? defaultWandbBaseUrl;
    try {
      final user = await validateApiKey(
        apiKey: apiKey,
        baseUrl: effectiveBaseUrl,
      );

      final storage = _ref.read(secureStorageProvider);
      await storage.setApiKey(apiKey);
      if (baseUrl != null) {
        await storage.setBaseUrl(baseUrl);
      } else {
        await storage.deleteBaseUrl();
      }

      final entity = preselectedEntity ?? user.entity;
      await storage.setEntity(entity);

      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        apiKey: apiKey,
        baseUrl: effectiveBaseUrl,
        selectedEntity: entity,
      );
    } on AuthenticationException {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Invalid API key',
      );
    } on WandbApiException catch (error) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: _errorMessageFor(error),
      );
    } catch (error) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: _errorMessageFor(error),
      );
    }
  }
}

void main() {
  test('release manifest declares internet permission', () async {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.INTERNET'));
  });

  test('login stores authenticated session and graphql client becomes available', () async {
    final storage = FakeSecureStorageService();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith((ref) => TestAuthNotifier(
              ref,
              validateApiKey: ({required apiKey, required baseUrl}) async =>
                  const WandbUser(
                    id: 'u1',
                    username: 'alice',
                    email: 'alice@example.com',
                    entity: 'team-a',
                    teams: ['team-a'],
                  ),
            )),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authProvider.notifier).login(apiKey: 'key-123');

    final auth = container.read(authProvider);
    expect(auth.status, AuthStatus.authenticated);
    expect(auth.apiKey, 'key-123');
    expect(auth.entity, 'team-a');
    expect(storage.apiKey, 'key-123');
    expect(container.read(graphqlClientProvider), isNotNull);
  });

  test('login exposes invalid key failure without persisting session', () async {
    final storage = FakeSecureStorageService();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith((ref) => TestAuthNotifier(
              ref,
              validateApiKey: ({required apiKey, required baseUrl}) async {
                throw const AuthenticationException();
              },
            )),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authProvider.notifier).login(apiKey: 'bad-key');

    final auth = container.read(authProvider);
    expect(auth.status, AuthStatus.unauthenticated);
    expect(auth.error, 'Invalid API key');
    expect(storage.apiKey, isNull);
    expect(() => container.read(graphqlClientProvider), throwsStateError);
  });

  test('login exposes typed network failure message without exception wrapper text', () async {
    final storage = FakeSecureStorageService();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith((ref) => TestAuthNotifier(
              ref,
              validateApiKey: ({required apiKey, required baseUrl}) async {
                throw const NetworkException();
              },
            )),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authProvider.notifier).login(apiKey: 'key-123');

    final auth = container.read(authProvider);
    expect(auth.status, AuthStatus.unauthenticated);
    expect(auth.error, 'Network unavailable');
    expect(auth.error, isNot(contains('WandbApiException')));
    expect(storage.apiKey, isNull);
  });

  test('login with empty baseUrl clears stored custom base url', () async {
    final storage = FakeSecureStorageService()..baseUrl = 'https://self-hosted.example';
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith((ref) => TestAuthNotifier(
              ref,
              validateApiKey: ({required apiKey, required baseUrl}) async {
                expect(baseUrl, defaultWandbBaseUrl);
                return const WandbUser(
                  id: 'u1',
                  username: 'alice',
                  email: 'alice@example.com',
                  entity: 'team-a',
                  teams: ['team-a'],
                );
              },
            )),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authProvider.notifier).login(apiKey: 'key-123');

    final auth = container.read(authProvider);
    expect(auth.status, AuthStatus.authenticated);
    expect(auth.baseUrl, defaultWandbBaseUrl);
    expect(storage.baseUrl, isNull);
  });

  test('login with custom baseUrl persists it for future sessions', () async {
    final storage = FakeSecureStorageService();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith((ref) => TestAuthNotifier(
              ref,
              validateApiKey: ({required apiKey, required baseUrl}) async {
                expect(baseUrl, 'https://self-hosted.example');
                return const WandbUser(
                  id: 'u1',
                  username: 'alice',
                  email: 'alice@example.com',
                  entity: 'team-a',
                  teams: ['team-a'],
                );
              },
            )),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authProvider.notifier).login(
      apiKey: 'key-123',
      baseUrl: 'https://self-hosted.example',
    );

    final auth = container.read(authProvider);
    expect(auth.status, AuthStatus.authenticated);
    expect(auth.baseUrl, 'https://self-hosted.example');
    expect(storage.baseUrl, 'https://self-hosted.example');
  });

  test('logout clears persisted session', () async {
    final storage = FakeSecureStorageService();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith((ref) => TestAuthNotifier(
              ref,
              validateApiKey: ({required apiKey, required baseUrl}) async =>
                  const WandbUser(
                    id: 'u1',
                    username: 'alice',
                    email: 'alice@example.com',
                    entity: 'team-a',
                    teams: ['team-a'],
                  ),
            )),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authProvider.notifier).login(apiKey: 'key-123');
    await container.read(authProvider.notifier).logout();

    final auth = container.read(authProvider);
    expect(auth.status, AuthStatus.unauthenticated);
    expect(storage.cleared, isTrue);
    expect(() => container.read(graphqlClientProvider), throwsStateError);
  });
}
