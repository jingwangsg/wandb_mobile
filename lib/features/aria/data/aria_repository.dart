import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/resource_refs.dart';
import '../../../core/app_configuration.dart';
import '../../auth/providers/auth_providers.dart';

class AriaTurn {
  const AriaTurn(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get threadId => data['thread_id'] as String;
  String get state => data['state'] as String;
  bool get active => state == 'queued' || state == 'in_progress';
  List<Map<String, dynamic>> get messages =>
      (data['messages'] as List? ?? [])
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
  List<Map<String, dynamic>> get tools =>
      (data['tool_calls'] as List? ?? [])
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
  List<Map<String, dynamic>> get questions =>
      (data['agent_questions'] as List? ?? [])
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
  String get prompt {
    final value = data['user_prompt'];
    if (value is String) return value;
    return (value as List? ?? [])
        .where((part) => part['type'] == 'text')
        .map((part) => part['text'])
        .join('\n');
  }
}

class AriaRepository {
  AriaRepository({
    required String apiKey,
    String wandbBaseUrl = defaultWandbBaseUrl,
  }) : _client = Dio(
         BaseOptions(
           baseUrl: 'https://wb-agent.wandb.ai/api/v1',
           headers: {
             if (sameSecureOrigin(wandbBaseUrl, defaultWandbBaseUrl))
               'Authorization':
                   'Basic ${base64Encode(utf8.encode('api:$apiKey'))}',
             'Content-Type': 'application/json',
           },
           followRedirects: false,
           connectTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 30),
         ),
       ) {
    if (!sameSecureOrigin(wandbBaseUrl, defaultWandbBaseUrl)) {
      _client.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (options, handler) => handler.reject(
                DioException(
                  requestOptions: options,
                  error: UnsupportedError(
                    'ARIA is available only for W&B Multi-tenant Cloud accounts.',
                  ),
                ),
              ),
        ),
      );
    }
  }
  final Dio _client;

  Future<AriaTurn> createTurn(
    String prompt, {
    ProjectRef? project,
    String? parentId,
    List<Map<String, dynamic>> references = const [],
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/turns',
      data: {
        'user_prompt':
            references.isEmpty
                ? prompt
                : [
                  {'type': 'text', 'text': prompt},
                  ...references,
                ],
        if (parentId != null) 'parent_turn_id': parentId,
        if (parentId == null && project != null) ...{
          'entity': project.entity,
          'project': project.project,
        },
      },
    );
    return AriaTurn(response.data!);
  }

  Future<AriaTurn> getTurn(String id, {CancelToken? cancelToken}) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/turns/${Uri.encodeComponent(id)}',
      cancelToken: cancelToken,
    );
    return AriaTurn(response.data!);
  }

  Future<List<AriaTurn>> turns(String threadId) async {
    final turns = <AriaTurn>[];
    for (var offset = 0; ; offset += 100) {
      final response = await _client.get<List<dynamic>>(
        '/turns',
        queryParameters: {
          'thread_id': threadId,
          'sort_by': 'created_at',
          'sort_desc': false,
          'limit': 100,
          'offset': offset,
        },
      );
      final page = response.data!;
      turns.addAll(
        page.map((item) => AriaTurn(Map<String, dynamic>.from(item as Map))),
      );
      if (page.length < 100) break;
    }
    return turns;
  }

  Future<List<Map<String, dynamic>>> threads({int offset = 0}) async {
    final response = await _client.get<List<dynamic>>(
      '/threads',
      queryParameters: {'sort_desc': true, 'limit': 30, 'offset': offset},
    );
    return response.data!
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> cancel(String id) =>
      _client.post<void>('/turns/${Uri.encodeComponent(id)}/cancel');
  Future<void> rename(String id, String title) => _client.patch<void>(
    '/threads/${Uri.encodeComponent(id)}',
    data: {'title': title},
  );
  Future<void> archive(String id) =>
      _client.post<void>('/threads/${Uri.encodeComponent(id)}/archive');
  Future<void> feedback(String id, bool positive, String reason) =>
      _client.post<void>(
        '/turns/${Uri.encodeComponent(id)}/feedback',
        data: {
          'feedback_is_positive': positive,
          'feedback_reasoning': reason,
          'share_turn_data_with_wandb': false,
        },
      );
  void dispose() => _client.close();
}

final ariaRepositoryProvider = Provider<AriaRepository>((ref) {
  final auth = ref.watch(
    authProvider.select((value) => (value.apiKey, value.baseUrl)),
  );
  final repository = AriaRepository(
    apiKey: auth.$1 ?? '',
    wandbBaseUrl: auth.$2 ?? defaultWandbBaseUrl,
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final ariaProjectContextProvider = StateProvider<ProjectRef?>((ref) {
  ref.watch(
    authProvider.select((auth) => (auth.user?.id, auth.selectedEntity)),
  );
  return null;
});

String ariaErrorMessage(Object error) {
  if (error is DioException) {
    if (error.error is UnsupportedError)
      return (error.error as UnsupportedError).message?.toString() ??
          'ARIA is unavailable for this server.';
    final data = error.response?.data;
    if (error.response?.statusCode == 401) return 'Sign in again to use ARIA.';
    if (error.response?.statusCode == 403)
      return 'ARIA requires a team account with Smart features enabled by your organization.';
    if (data is Map && data['error'] is Map)
      return data['error']['message']?.toString() ??
          'ARIA is unavailable. Please retry.';
  }
  return 'Unable to connect to ARIA. Please try again.';
}
