import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_configuration.dart';
import '../../../core/models/resource_refs.dart';
import '../../auth/providers/auth_providers.dart';

class NotificationRule {
  const NotificationRule({
    required this.id,
    required this.entity,
    required this.project,
    required this.name,
    this.metric,
    this.status = 'active',
  });
  final String id;
  final String entity;
  final String project;
  final String name;
  final String? metric;
  final String status;

  factory NotificationRule.fromJson(Map<String, dynamic> json) =>
      NotificationRule(
        id: json['id'] as String,
        entity: json['entity'] as String,
        project: json['project'] as String,
        name: json['name'] as String,
        metric: json['metric'] as String?,
        status: json['status'] as String? ?? 'active',
      );
}

class NotificationsRepository {
  NotificationsRepository({
    required String apiKey,
    required String baseUrl,
    String wandbBaseUrl = defaultWandbBaseUrl,
    String relayWandbBaseUrl = AppConfiguration.pushWandbBaseUrl,
  }) : _client = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           headers: {
             if (sameSecureOrigin(wandbBaseUrl, relayWandbBaseUrl) &&
                 sameSecureOrigin(baseUrl, baseUrl))
               'Authorization':
                   'Basic ${base64Encode(utf8.encode('api:$apiKey'))}',
           },
           connectTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 30),
           followRedirects: false,
         ),
       ) {
    if (!sameSecureOrigin(wandbBaseUrl, relayWandbBaseUrl) ||
        (baseUrl.isNotEmpty && !sameSecureOrigin(baseUrl, baseUrl))) {
      _client.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (options, handler) => handler.reject(
                DioException(
                  requestOptions: options,
                  error: UnsupportedError(
                    'This push service is not configured for your W&B server.',
                  ),
                ),
              ),
        ),
      );
    }
  }
  final Dio _client;

  Future<List<NotificationRule>> rules() async {
    if (_client.options.baseUrl.isEmpty) {
      throw StateError('Push notifications are not configured for this build.');
    }
    final response = await _client.get<List<dynamic>>('/v1/subscriptions');
    return response.data!
        .map(
          (item) =>
              NotificationRule.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> create({
    required ProjectRef project,
    String? metric,
    String direction = 'ANY',
    String basis = 'ABSOLUTE',
    double? amount,
  }) async {
    if (_client.options.baseUrl.isEmpty) {
      throw StateError('Push notifications are not configured for this build.');
    }
    await _client.post<void>(
      '/v1/subscriptions',
      data: {
        'entity': project.entity,
        'project': project.project,
        if (metric != null) 'metric': metric,
        'direction': direction,
        'basis': basis,
        if (amount != null) 'amount': amount,
      },
    );
  }

  Future<void> delete(String id) =>
      _client.delete<void>('/v1/subscriptions/${Uri.encodeComponent(id)}');

  Future<void> registerDevice(String token) =>
      _client.put<void>('/v1/devices', data: {'token': token});

  Future<void> unregisterDevice(String token) =>
      _client.delete<void>('/v1/devices', data: {'token': token});

  void dispose() => _client.close();
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  final auth = ref.watch(
    authProvider.select((value) => (value.apiKey, value.baseUrl)),
  );
  final repository = NotificationsRepository(
    apiKey: auth.$1 ?? '',
    baseUrl: AppConfiguration.pushRelayUrl,
    wandbBaseUrl: auth.$2 ?? defaultWandbBaseUrl,
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final notificationRulesProvider =
    FutureProvider.autoDispose<List<NotificationRule>>(
      (ref) => ref.watch(notificationsRepositoryProvider).rules(),
    );
