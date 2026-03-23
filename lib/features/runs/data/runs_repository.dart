import 'dart:convert';

import '../../../core/api/graphql_client.dart';
import '../../../core/api/graphql_queries.dart';
import '../../../core/models/metric_point.dart';
import '../../../core/models/paginated.dart';
import '../../../core/models/run.dart';
import '../../../core/models/run_file.dart';

class RunsRepository {
  const RunsRepository(this._client);
  final GraphqlClient _client;
  static const _chartAxisKeys = ['_step', '_timestamp'];

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
    final requestedKeys = <String>[
      ..._chartAxisKeys,
      ...keys.where((key) => !_chartAxisKeys.contains(key)),
    ];
    final spec = jsonEncode({'keys': requestedKeys, 'samples': samples});
    final data = await _client.query(
      WandbQueries.getSampledHistory,
      variables: {
        'entity': entity,
        'project': project,
        'run': runName,
        'spec': spec,
      },
    );

    final run = (data['project'] as Map)['run'] as Map<String, dynamic>;
    final historyArrays = run['sampledHistory'] as List;

    if (historyArrays.isEmpty) return [];

    // sampledHistory returns [[{_step, key1, key2, ...}, ...]]
    final rows = historyArrays.first as List;

    // Build MetricSeries for each requested key
    return keys.map((key) {
      final points = <MetricPoint>[];
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        final map = row as Map<String, dynamic>;
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
  }) async {
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
}
