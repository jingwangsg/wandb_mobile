import 'dart:convert';

import '../../../core/api/graphql_client.dart';
import '../../../core/api/graphql_queries.dart';
import '../../../core/api/mobile_queries.dart';
import '../../../core/api/api_exceptions.dart';
import '../../../core/models/metric_point.dart';
import '../../../core/models/paginated.dart';
import '../../../core/models/run.dart';
import '../../../core/models/run_file.dart';
import '../../../core/models/run_log.dart';

class RunsRepository {
  const RunsRepository(this._client);
  final GraphqlClient _client;
  static const _chartAxisKeys = ['_step', '_timestamp'];

  Future<WandbRun> getRun({
    required String entity,
    required String project,
    required String runName,
  }) async {
    final data = await _client.query(
      MobileQueries.run,
      variables: {'entity': entity, 'project': project, 'run': runName},
    );
    final run = (data['project'] as Map?)?['run'] as Map<String, dynamic>?;
    if (run == null) {
      throw const NotFoundException('Run not found or access denied');
    }
    return WandbRun.fromJson(run);
  }

  Future<PaginatedResult<WandbRun>> getRecentRuns({
    String? cursor,
    String? pattern,
  }) async {
    final data = await _client.query(
      MobileQueries.recentRuns,
      variables: {'cursor': cursor, 'pattern': pattern},
    );
    final viewer = data['viewer'] as Map?;
    if (viewer == null) throw const AuthenticationException();
    final runs = viewer['runs'] as Map;
    return PaginatedResult(
      items:
          (runs['edges'] as List)
              .map(
                (edge) =>
                    WandbRun.fromJson(edge['node'] as Map<String, dynamic>),
              )
              .toList(),
      endCursor: runs['pageInfo']['endCursor'] as String?,
      hasNextPage: runs['pageInfo']['hasNextPage'] as bool,
    );
  }

  Future<void> stopRun(String id) async {
    final data = await _client.query(
      MobileQueries.stopRun,
      variables: {'id': id},
    );
    if (data['stopRun']?['success'] != true) {
      throw const ServerException('The run could not be stopped');
    }
  }

  Future<Map<String, dynamic>> getProjectMetrics({
    required String entity,
    required String project,
  }) async {
    final data = await _client.query(
      MobileQueries.projectMetrics,
      variables: {'entity': entity, 'project': project},
    );
    final value = data['project']?['runs']?['historyKeys'];
    if (value is String) return jsonDecode(value) as Map<String, dynamic>;
    return Map<String, dynamic>.from(value as Map? ?? {});
  }

  Future<RunLogPage> getLogs({
    required String entity,
    required String project,
    required String runName,
    String? before,
    String? after,
    int limit = 10000,
  }) async {
    final data = await _client.query(
      MobileQueries.logs,
      variables: {
        'entity': entity,
        'project': project,
        'run': runName,
        'before': before,
        'after': after,
        if (after == null) 'last': limit else 'first': limit,
      },
    );
    final logs = data['project']?['run']?['logLines'] as Map?;
    if (logs == null) throw const NotFoundException('Run logs are unavailable');
    final page = logs['pageInfo'] as Map;
    return RunLogPage(
      lines:
          (logs['edges'] as List)
              .map(
                (edge) => RunLogLine(
                  cursor: edge['cursor'] as String,
                  text: edge['node']['line'] as String? ?? '',
                  number: edge['node']['number'] as int?,
                  timestamp: edge['node']['timestamp'] as String?,
                ),
              )
              .toList(),
      startCursor: page['startCursor'] as String?,
      endCursor: page['endCursor'] as String?,
      hasPreviousPage: page['hasPreviousPage'] as bool? ?? false,
      hasNextPage: page['hasNextPage'] as bool? ?? false,
    );
  }

  /// List runs with optional filters and sorting.
  Future<PaginatedResult<WandbRun>> getRuns({
    required String entity,
    required String project,
    String? cursor,
    int perPage = 20,
    String? order,
    Map<String, dynamic>? filters,
  }) async {
    final data = await _client.query(
      WandbQueries.getRuns,
      variables: {
        'entity': entity,
        'project': project,
        'cursor': cursor,
        'perPage': perPage,
        if (order != null) 'order': order,
        if (filters != null) 'filters': jsonEncode(filters),
      },
    );

    final proj = data['project'] as Map<String, dynamic>;
    final runsData = proj['runs'] as Map<String, dynamic>;
    final pageInfo = runsData['pageInfo'] as Map<String, dynamic>;
    final edges = runsData['edges'] as List;
    final totalCount = proj['runCount'] as int?;

    return PaginatedResult(
      items:
          edges
              .map((e) => WandbRun.fromJson(e['node'] as Map<String, dynamic>))
              .toList(),
      endCursor: pageInfo['endCursor'] as String?,
      hasNextPage: pageInfo['hasNextPage'] as bool? ?? false,
      totalCount: totalCount,
    );
  }

  /// Get sampled history for chart rendering.
  /// Returns a list of MetricSeries, one per requested key.
  Future<List<MetricSeries>> getSampledHistory({
    required String entity,
    required String project,
    required String runName,
    required List<String> keys,
    int samples = 500,
  }) async {
    final requestedKeys = keys
        .where((key) => !_chartAxisKeys.contains(key))
        .toList(growable: false);
    if (requestedKeys.isEmpty) return [];

    final specs = requestedKeys
        .map(
          (key) => jsonEncode({
            'keys': [..._chartAxisKeys, key],
            'samples': samples,
          }),
        )
        .toList(growable: false);
    final data = await _client.query(
      WandbQueries.getSampledHistory,
      variables: {
        'entity': entity,
        'project': project,
        'run': runName,
        'specs': specs,
      },
    );

    final run = (data['project'] as Map)['run'] as Map<String, dynamic>;
    final historyArrays = run['sampledHistory'] as List;

    return requestedKeys.asMap().entries.map((entry) {
      final key = entry.value;
      final rows =
          entry.key < historyArrays.length && historyArrays[entry.key] is List
              ? historyArrays[entry.key] as List
              : const [];
      final points = <MetricPoint>[];
      for (var index = 0; index < rows.length; index++) {
        final map = _sampledHistoryRowAsMap(rows[index]);
        final value = map[key];
        if (value is! num) continue;

        final rawStep = map['_step'];
        final step = rawStep is num ? rawStep : index;

        final rawTimestamp = map['_timestamp'];
        final timestamp =
            rawTimestamp is num
                ? DateTime.fromMillisecondsSinceEpoch(
                  rawTimestamp.toInt() * 1000,
                )
                : null;

        points.add(
          MetricPoint(
            step: step,
            value: value.toDouble(),
            timestamp: timestamp,
          ),
        );
      }
      return MetricSeries(key: key, points: points);
    }).toList();
  }

  /// Get full history for a step range (used when zoomed in).
  Future<List<Map<String, dynamic>>> getHistoryPage({
    required String entity,
    required String project,
    required String runName,
    required int minStep,
    required int maxStep,
    int pageSize = 500,
    List<String>? keys,
  }) async {
    if (keys != null) {
      final data = await _client.query(
        WandbQueries.getSampledHistory,
        variables: {
          'entity': entity,
          'project': project,
          'run': runName,
          'specs': [
            jsonEncode({
              'keys': ['_step', ...keys],
              'minStep': minStep,
              'maxStep': maxStep,
              'samples': pageSize,
            }),
          ],
        },
      );
      final history = data['project']['run']['sampledHistory'] as List;
      return (history.first as List).map(_sampledHistoryRowAsMap).toList();
    }
    final data = await _client.query(
      WandbQueries.getHistoryPage,
      variables: {
        'entity': entity,
        'project': project,
        'run': runName,
        'minStep': minStep,
        'maxStep': maxStep,
        'pageSize': pageSize,
      },
    );

    final run = (data['project'] as Map)['run'] as Map<String, dynamic>;
    final history = run['history'] as List;
    return history.map((row) {
      if (row is String) return jsonDecode(row) as Map<String, dynamic>;
      return row as Map<String, dynamic>;
    }).toList();
  }

  /// Get system metrics (CPU, GPU, memory).
  Future<List<Map<String, dynamic>>> getSystemMetrics({
    required String entity,
    required String project,
    required String runName,
    int samples = 500,
  }) async {
    final data = await _client.query(
      WandbQueries.getRunEvents,
      variables: {
        'entity': entity,
        'project': project,
        'name': runName,
        'samples': samples,
      },
    );

    final run = (data['project'] as Map)['run'] as Map<String, dynamic>;
    final events = run['events'] as List;
    return events.map((row) {
      if (row is String) return jsonDecode(row) as Map<String, dynamic>;
      return row as Map<String, dynamic>;
    }).toList();
  }

  /// Get files for a run.
  Future<PaginatedResult<RunFile>> getRunFiles({
    required String entity,
    required String project,
    required String runName,
    String? cursor,
    int limit = 50,
    List<String>? fileNames,
  }) async {
    final data = await _client.query(
      WandbQueries.getRunFiles,
      variables: {
        'entity': entity,
        'project': project,
        'name': runName,
        'fileCursor': cursor,
        'fileLimit': limit,
        if (fileNames != null) 'fileNames': fileNames,
      },
    );

    final run = (data['project'] as Map)['run'] as Map<String, dynamic>;
    final filesData = run['files'] as Map<String, dynamic>;
    final pageInfo = filesData['pageInfo'] as Map<String, dynamic>;
    final edges = filesData['edges'] as List;
    final totalCount = run['fileCount'] as int?;

    return PaginatedResult(
      items:
          edges
              .map((e) => RunFile.fromJson(e['node'] as Map<String, dynamic>))
              .toList(),
      endCursor: pageInfo['endCursor'] as String?,
      hasNextPage: pageInfo['hasNextPage'] as bool? ?? false,
      totalCount: totalCount,
    );
  }

  /// Get console log content.
  Future<String?> getConsoleLog({
    required String entity,
    required String project,
    required String runName,
  }) async {
    final result = await getRunFiles(
      entity: entity,
      project: project,
      runName: runName,
      fileNames: ['output.log'],
    );

    if (result.items.isEmpty) return null;
    final logFile = result.items.first;

    // Download the file content via directUrl
    final url = logFile.directUrl ?? logFile.url;
    if (url == null) return null;

    // Use Dio from the client to download
    // For simplicity, return the URL — the UI layer will handle download
    return url;
  }

  static Map<String, dynamic> _sampledHistoryRowAsMap(dynamic row) {
    if (row is Map<String, dynamic>) return row;
    if (row is Map) {
      return row.map((key, value) => MapEntry(key.toString(), value));
    }
    if (row is String) {
      final decoded = jsonDecode(row);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return const {};
  }
}
