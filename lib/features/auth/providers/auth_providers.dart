import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exceptions.dart';
import '../../../core/api/graphql_client.dart';
import '../../../core/diagnostics/runtime_diagnostics.dart';
import '../../../core/models/user.dart';
import '../../../core/providers/api_client_provider.dart';
import '../data/auth_repository.dart';

/// Auth state: loading / authenticated / unauthenticated.
enum AuthStatus { loading, authenticated, unauthenticated }

const defaultWandbBaseUrl = 'https://api.wandb.ai';

class AuthState {
  const AuthState({
    this.status = AuthStatus.loading,
    this.user,
    this.apiKey,
    this.baseUrl,
    this.error,
    this.selectedEntity,
  });

  final AuthStatus status;
  final WandbUser? user;
  final String? apiKey;
  final String? baseUrl;
  final String? error;
  final String? selectedEntity;

  String get entity => selectedEntity ?? user?.entity ?? '';

  AuthState copyWith({
    AuthStatus? status,
    WandbUser? user,
    String? apiKey,
    String? baseUrl,
    String? error,
    String? selectedEntity,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
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
  RuntimeDiagnostics get _diagnostics => RuntimeDiagnostics.instance;

  static String _errorMessageFor(Object error) {
    if (error is WandbApiException) {
      return error.message;
    }
    return error.toString();
  }

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

    final effectiveBaseUrl = baseUrl ?? defaultWandbBaseUrl;
    _diagnostics.record(
      'auth_login_start',
      'Starting login request',
      data: {'baseUrl': effectiveBaseUrl},
    );

    final client = GraphqlClient(
      apiKey: apiKey,
      baseUrl: effectiveBaseUrl,
    );

    try {
      final repo = AuthRepository(client);
      final user = await repo.validateApiKey();
      _diagnostics.record(
        'auth_login_success',
        'Login succeeded',
        data: {'username': user.username, 'entity': user.entity},
      );

      // Persist credentials
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
      client.dispose();
    } on AuthenticationException {
      _diagnostics.record(
        'auth_login_failure',
        'Invalid API key',
      );
      client.dispose();
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Invalid API key',
      );
    } on WandbApiException catch (e, st) {
      _diagnostics.record(
        'auth_login_failure',
        e.message,
        stackTrace: st,
      );
      client.dispose();
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: _errorMessageFor(e),
      );
    } catch (e, st) {
      _diagnostics.record(
        'auth_login_failure',
        e.toString(),
        stackTrace: st,
      );
      client.dispose();
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: _errorMessageFor(e),
      );
    }
  }

  Future<void> selectEntity(String entity) async {
    final storage = _ref.read(secureStorageProvider);
    await storage.setEntity(entity);
    state = state.copyWith(selectedEntity: entity);
  }

  Future<void> logout() async {
    final storage = _ref.read(secureStorageProvider);
    await storage.clearAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authProvider.select((state) => state.status));
});

/// Convenience provider to get a non-null GraphqlClient.
/// Throws if not authenticated.
final graphqlClientProvider = Provider<GraphqlClient>((ref) {
  final auth = ref.watch(authProvider);
  final apiKey = auth.apiKey;
  if (apiKey == null || apiKey.isEmpty) {
    throw StateError('Not authenticated');
  }
  final client = GraphqlClient(
    apiKey: apiKey,
    baseUrl: auth.baseUrl ?? defaultWandbBaseUrl,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Current selected entity.
final currentEntityProvider = Provider<String>((ref) {
  return ref.watch(authProvider).entity;
});
