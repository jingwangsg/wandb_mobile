import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import '../diagnostics/runtime_diagnostics.dart';

/// Thin GraphQL client wrapping Dio.
/// Sends POST to /graphql with JSON body {"query": "...", "variables": {...}}.
class GraphqlClient {
  GraphqlClient({
    required String apiKey,
    String baseUrl = 'https://api.wandb.ai',
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {
            'Content-Type': 'application/json',
            'Authorization':
                'Basic ${base64Encode(utf8.encode('api:$apiKey'))}',
          },
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        )) {
    _dio.interceptors.add(_RetryInterceptor(_dio));
  }

  final Dio _dio;

  /// Execute a GraphQL query/mutation.
  /// Returns the `data` field from the response.
  /// Throws typed [WandbApiException] on error.
  Future<Map<String, dynamic>> query(
    String queryString, {
    Map<String, dynamic>? variables,
  }) async {
    final operationName = _extractOperationName(queryString);
    try {
      RuntimeDiagnostics.instance.record(
        'graphql_request',
        'Starting $operationName',
        data: {
          'operation': operationName,
          'baseUrl': _dio.options.baseUrl,
          if (variables != null) 'variables': variables,
        },
      );

      final response = await _dio.post<Map<String, dynamic>>(
        '/graphql',
        data: {
          'query': queryString,
          if (variables != null) 'variables': variables,
        },
      );

      final body = response.data!;

      // Check for GraphQL-level errors
      if (body.containsKey('errors')) {
        final errors = (body['errors'] as List)
            .cast<Map<String, dynamic>>();
        if (errors.isNotEmpty) {
          RuntimeDiagnostics.instance.record(
            'graphql_error',
            '$operationName returned GraphQL errors',
            data: {
              'operation': operationName,
              if (variables != null) 'variables': variables,
              'errors': errors,
            },
          );
          throw GraphQLException(errors, errors.first['message'] as String? ?? 'Unknown GraphQL error');
        }
      }

      if (operationName == 'SampledHistoryPage') {
        RuntimeDiagnostics.instance.record(
          'graphql_response',
          '$operationName succeeded',
          data: {
            'operation': operationName,
            if (variables != null) 'variables': variables,
            ..._responseSummary(body['data']),
          },
        );
      }

      return body['data'] as Map<String, dynamic>? ?? {};
    } on DioException catch (e, st) {
      RuntimeDiagnostics.instance.record(
        'graphql_network_error',
        '$operationName failed before GraphQL parsing',
        data: {
          'operation': operationName,
          if (variables != null) 'variables': variables,
          'statusCode': e.response?.statusCode,
          'type': e.type.name,
          if (e.response?.data != null)
            'response': e.response?.data.toString(),
        },
        stackTrace: st,
      );
      throw _mapDioException(e);
    }
  }

  /// Update the API key (e.g. after re-authentication).
  void updateApiKey(String apiKey) {
    _dio.options.headers['Authorization'] =
        'Basic ${base64Encode(utf8.encode('api:$apiKey'))}';
  }

  /// Update the base URL (e.g. for self-hosted instances).
  void updateBaseUrl(String baseUrl) {
    _dio.options.baseUrl = baseUrl;
  }

  void dispose() {
    _dio.close();
  }

  static WandbApiException _mapDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    switch (statusCode) {
      case 401:
        return const AuthenticationException();
      case 403:
        return const ForbiddenException();
      case 404:
        return const NotFoundException();
      case 429:
        final retryAfter = e.response?.headers.value('retry-after');
        return RateLimitException(
          retryAfter: retryAfter != null
              ? Duration(seconds: int.tryParse(retryAfter) ?? 30)
              : const Duration(seconds: 30),
        );
      case final code when code != null && code >= 500:
        return ServerException('Server error: $statusCode');
      default:
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.error is SocketException) {
          return const NetworkException();
        }
        return NetworkException(e.message ?? 'Unknown network error');
    }
  }

  static String _extractOperationName(String queryString) {
    final match = RegExp(
      r'(query|mutation)\s+([A-Za-z0-9_]+)',
      multiLine: true,
    ).firstMatch(queryString);
    return match?.group(2) ?? 'AnonymousOperation';
  }

  static Map<String, Object?> _responseSummary(Object? data) {
    if (data is! Map<String, dynamic>) {
      return {'dataType': data.runtimeType.toString()};
    }

    final summary = <String, Object?>{
      'dataKeys': data.keys.toList(growable: false),
    };

    final project = data['project'];
    if (project is Map<String, dynamic>) {
      final run = project['run'];
      if (run is Map<String, dynamic>) {
        final sampledHistory = run['sampledHistory'];
        if (sampledHistory is List && sampledHistory.isNotEmpty) {
          final firstSeries = sampledHistory.first;
          summary['sampledHistorySeriesCount'] = sampledHistory.length;
          if (firstSeries is List) {
            summary['sampledHistoryRowCount'] = firstSeries.length;
          }
        }
      }
    }

    return summary;
  }
}

/// Retry interceptor with exponential backoff for 429 and 5xx.
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);

  final Dio _dio;
  static const _maxRetries = 3;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final shouldRetry =
        statusCode == 429 || (statusCode != null && statusCode >= 500);

    if (!shouldRetry) {
      handler.next(err);
      return;
    }

    final retries = err.requestOptions.extra['_retryCount'] as int? ?? 0;
    if (retries >= _maxRetries) {
      handler.next(err);
      return;
    }

    // Exponential backoff: 1s, 2s, 4s
    final delay = Duration(seconds: 1 << retries);

    // Respect Retry-After header on 429
    final retryAfterHeader = err.response?.headers.value('retry-after');
    final actualDelay = retryAfterHeader != null
        ? Duration(seconds: int.tryParse(retryAfterHeader) ?? delay.inSeconds)
        : delay;

    await Future<void>.delayed(actualDelay);

    final options = err.requestOptions;
    options.extra['_retryCount'] = retries + 1;

    try {
      final response = await _dio.fetch(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
