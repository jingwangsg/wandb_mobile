import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exceptions.dart';
import '../../../core/api/graphql_client.dart';
import '../../../core/models/user.dart';
import '../../../core/providers/api_client_provider.dart';
import '../data/auth_repository.dart';

/// Auth state: loading / authenticated / unauthenticated.
enum AuthStatus { loading, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.loading,
    this.user,
    this.apiClient,
    this.error,
    this.selectedEntity,
  });

  final AuthStatus status;
  final WandbUser? user;
  final GraphqlClient? apiClient;
  final String? error;
  final String? selectedEntity;

  String get entity => selectedEntity ?? user?.entity ?? '';

  AuthState copyWith({
    AuthStatus? status,
    WandbUser? user,
    GraphqlClient? apiClient,
    String? error,
    String? selectedEntity,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      apiClient: apiClient ?? this.apiClient,
      error: error,
      selectedEntity: selectedEntity ?? this.selectedEntity,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState()) {
    _tryAutoLogin();
  }

  final Ref _ref;

  Future<void> _tryAutoLogin() async {
    final storage = _ref.read(secureStorageProvider);
    var apiKey = await storage.getApiKey();

    // DEV: auto-login for testing
    if (apiKey == null || apiKey.isEmpty) {
      apiKey = const String.fromEnvironment('WANDB_API_KEY');
    }

    if (apiKey.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }

    final baseUrl = await storage.getBaseUrl();
    final entity = await storage.getEntity();

    await login(
      apiKey: apiKey,
      baseUrl: baseUrl,
      preselectedEntity: entity,
    );
  }

  Future<void> login({
    required String apiKey,
    String? baseUrl,
    String? preselectedEntity,
  }) async {
    state = const AuthState(status: AuthStatus.loading);

    final effectiveBaseUrl = baseUrl ?? 'https://api.wandb.ai';
    print('[AUTH] login: connecting to $effectiveBaseUrl');

    final client = GraphqlClient(
      apiKey: apiKey,
      baseUrl: effectiveBaseUrl,
    );

    try {
      final repo = AuthRepository(client);
      print('[AUTH] calling validateApiKey...');
      final user = await repo.validateApiKey();
      print('[AUTH] success: ${user.username} / ${user.entity}');

      // Persist credentials
      final storage = _ref.read(secureStorageProvider);
      await storage.setApiKey(apiKey);
      if (baseUrl != null) await storage.setBaseUrl(baseUrl);

      final entity = preselectedEntity ?? user.entity;
      await storage.setEntity(entity);

      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        apiClient: client,
        selectedEntity: entity,
      );
    } on AuthenticationException {
      print('[AUTH] error: invalid API key');
      client.dispose();
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Invalid API key',
      );
    } catch (e, st) {
      print('[AUTH] error: $e');
      print('[AUTH] stacktrace: $st');
      client.dispose();
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
    }
  }

  Future<void> selectEntity(String entity) async {
    final storage = _ref.read(secureStorageProvider);
    await storage.setEntity(entity);
    state = state.copyWith(selectedEntity: entity);
  }

  Future<void> logout() async {
    state.apiClient?.dispose();
    final storage = _ref.read(secureStorageProvider);
    await storage.clearAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

/// Convenience provider to get a non-null GraphqlClient.
/// Throws if not authenticated.
final graphqlClientProvider = Provider<GraphqlClient>((ref) {
  final auth = ref.watch(authProvider);
  final client = auth.apiClient;
  if (client == null) {
    throw StateError('Not authenticated');
  }
  return client;
});

/// Current selected entity.
final currentEntityProvider = Provider<String>((ref) {
  return ref.watch(authProvider).entity;
});
