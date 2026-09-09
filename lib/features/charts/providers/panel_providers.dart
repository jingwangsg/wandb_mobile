import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/metric_point.dart';
import '../../../core/models/resource_refs.dart';
import '../../../core/providers/mobile_preferences.dart';
import '../../runs/providers/runs_providers.dart';
import '../../runs/utils/metric_selection.dart';

typedef PanelRequest = ({ProjectRef project, String? runName, String metric});

final panelRefreshProvider = StateProvider.autoDispose
    .family<int, ({ProjectRef project, String? runName})>((ref, _) => 0);

final projectMetricKeysProvider = FutureProvider.autoDispose
    .family<List<String>, ProjectRef>((ref, project) async {
      final result = await ref
          .watch(runsRepositoryProvider)
          .getProjectMetrics(entity: project.entity, project: project.project);
      final keys = result['keys'] as Map? ?? result;
      return keys.keys
          .cast<String>()
          .where((key) => !key.startsWith('_') && !isSystemMetric(key))
          .toList()
        ..sort();
    });

final panelSeriesProvider = FutureProvider.autoDispose.family<
  List<MetricSeries>,
  PanelRequest
>((ref, request) async {
  ref.watch(
    panelRefreshProvider((project: request.project, runName: request.runName)),
  );
  final repository = ref.watch(runsRepositoryProvider);
  if (request.runName != null) {
    return repository.getSampledHistory(
      entity: request.project.entity,
      project: request.project.project,
      runName: request.runName!,
      keys: [request.metric],
    );
  }
  final hidden = ref.watch(
    mobilePreferencesProvider.select(
      (value) => value.hiddenRuns[request.project.path],
    ),
  );
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final lines = <MetricSeries>[];
  String? cursor;
  do {
    final page = await repository.getRuns(
      entity: request.project.entity,
      project: request.project.project,
      cursor: cursor,
      perPage: 100,
    );
    if (disposed) return lines;
    final runs =
        page.items.where((run) => hidden?.contains(run.name) != true).toList();
    for (var start = 0; start < runs.length; start += 6) {
      final end = (start + 6).clamp(0, runs.length);
      final batch = await Future.wait(
        runs.sublist(start, end).map((run) async {
          final history = await repository.getSampledHistory(
            entity: request.project.entity,
            project: request.project.project,
            runName: run.name,
            keys: [request.metric],
          );
          return MetricSeries(
            key: '${run.displayName} (${run.name})',
            points: history.firstOrNull?.points ?? [],
          );
        }),
      );
      lines.addAll(batch.where((line) => !line.isEmpty));
      if (disposed) return lines;
    }
    if (!page.hasNextPage) break;
    if (page.endCursor == null || page.endCursor == cursor) {
      throw StateError('Project runs did not advance to the next page');
    }
    cursor = page.endCursor;
  } while (true);
  return lines;
});

final runSystemSeriesProvider = FutureProvider.autoDispose
    .family<List<MetricSeries>, RunRef>((ref, run) async {
      final rows = await ref
          .watch(runsRepositoryProvider)
          .getSystemMetrics(
            entity: run.entity,
            project: run.project,
            runName: run.runName,
          );
      final points = <String, List<MetricPoint>>{};
      for (final (index, row) in rows.indexed) {
        final numeric = <String, double>{};
        flattenSystemMetrics(row, numeric);
        final rawTimestamp = row['_timestamp'];
        final timestamp =
            rawTimestamp is num
                ? DateTime.fromMillisecondsSinceEpoch(
                  (rawTimestamp * 1000).round(),
                )
                : null;
        for (final entry in numeric.entries) {
          (points[entry.key] ??= []).add(
            MetricPoint(
              step: row['_step'] as num? ?? index,
              value: entry.value,
              timestamp: timestamp,
            ),
          );
        }
      }
      return points.entries
          .map((entry) => MetricSeries(key: entry.key, points: entry.value))
          .toList();
    });

void flattenSystemMetrics(
  Map row,
  Map<String, double> output, [
  String prefix = '',
]) {
  for (final entry in row.entries) {
    final key = entry.key.toString();
    if (key.startsWith('_') || (prefix.isEmpty && key == 'timestamp')) continue;
    final path = prefix.isEmpty ? key : '$prefix/$key';
    final value = entry.value;
    if (value is Map) {
      flattenSystemMetrics(value, output, path);
    } else if (value is num && value.isFinite) {
      // Events use system.cpu; history metadata calls the same key system/cpu.
      final metric =
          path.startsWith('system.')
              ? 'system/${path.substring('system.'.length)}'
              : path;
      output[metric] = value.toDouble();
    }
  }
}

bool isMetricStarred(
  MobilePreferences preferences,
  ProjectRef project,
  String metric,
) => preferences.starredMetrics.contains(jsonEncode([project.path, metric]));
