import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/runtime_diagnostics.dart';
import '../../../core/models/metric_point.dart';
import '../../../core/models/resource_refs.dart';
import '../../../core/models/run.dart';
import '../../../core/providers/mobile_preferences.dart';
import '../../auth/providers/auth_providers.dart';
import '../../runs/providers/runs_providers.dart';
import '../../runs/utils/metric_selection.dart';
import '../models/workspace_settings.dart';

typedef PanelRequest = ({ProjectRef project, String? runName, String metric});

/// Runs considered for project panels. [candidates] were listed with the Runs
/// tab's filters and order; [visible] is the drawn subset, at most [limit].
typedef VisibleRuns =
    ({
      List<WandbRun> candidates,
      List<WandbRun> visible,
      int limit,
      int? totalCount,
    });

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

/// The user's personal W&B web workspace for the project, or null when it is
/// unavailable. Any failure (no views on this host, permissions, offline)
/// falls back to app defaults instead of blocking the panels that await it.
final workspaceSettingsProvider = FutureProvider.autoDispose
    .family<WorkspaceSettings?, ProjectRef>((ref, project) async {
      try {
        // Panels only exist for an authenticated session, so the username is
        // read once; watching it would re-run every panel on auth updates.
        final username = ref.read(authProvider).user?.username;
        if (username == null) return null;
        return await ref
            .watch(runsRepositoryProvider)
            .getWorkspaceSettings(
              entity: project.entity,
              project: project.project,
              username: username,
            );
      } catch (error) {
        RuntimeDiagnostics.instance.record(
          'workspace_settings',
          'Using app defaults for ${project.path}: $error',
        );
        return null;
      }
    });

/// Whether a run is drawn in project panels: the app's own toggle wins, then
/// the web workspace's run selection, then visible.
bool isRunVisible(
  Map<String, bool>? overrides,
  WorkspaceSettings? workspace,
  String runName,
) => overrides?[runName] ?? workspace?.isRunVisible(runName) ?? true;

final visibleRunsProvider = FutureProvider.autoDispose.family<
  VisibleRuns,
  ProjectRef
>((ref, project) async {
  ref.watch(panelRefreshProvider((project: project, runName: null)));
  final repository = ref.watch(runsRepositoryProvider);
  final filters = ref.watch(runFiltersProvider(project));
  final (overrides, storedLimit) = ref.watch(
    mobilePreferencesProvider.select(
      (value) => (
        value.runVisibility[project.path],
        value.visibleRunLimits[project.path],
      ),
    ),
  );
  // A rebuild disposes this build while it may still be awaiting; stop
  // early so a superseded build does not keep paging.
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final workspace = await ref.watch(workspaceSettingsProvider(project).future);
  final limit = storedLimit ?? workspace?.maxRuns ?? 10;
  final tabFilters = filters.toApiFilters();
  final candidates = <WandbRun>[];
  final visible = <WandbRun>[];
  int? totalCount;

  // Pages in the Runs tab's order, keeping eligible runs until [limit].
  Future<void> collect(Map<String, dynamic>? apiFilters, int maxPages) async {
    String? cursor;
    for (
      var page = 0;
      page < maxPages && !disposed && visible.length < limit;
      page++
    ) {
      final result = await repository.getRuns(
        entity: project.entity,
        project: project.project,
        cursor: cursor,
        // Page at least 20 so sparse selections do not crawl tiny pages.
        perPage: max(limit, 20),
        order: filters.order,
        filters: apiFilters,
      );
      totalCount ??= result.totalCount;
      candidates.addAll(result.items);
      visible.addAll(
        result.items
            .where((run) => isRunVisible(overrides, workspace, run.name))
            .take(limit - visible.length),
      );
      if (!result.hasNextPage) return;
      if (result.endCursor == null || result.endCursor == cursor) {
        throw StateError('Project runs did not advance to the next page');
      }
      cursor = result.endCursor;
    }
  }

  // Newest runs first, as the Runs tab lists them. Scan at most five pages
  // so hiding most recent runs cannot crawl the whole project; an explicit
  // web selection needs one page here because its runs are fetched by name.
  final allowlist =
      workspace == null || workspace.allRunsSelected
          ? null
          : workspace.selectionExceptions;
  await collect(tabFilters, allowlist == null ? 5 : 1);

  // Runs shown explicitly, by the web selection or an app toggle, may be
  // older than the pages scanned; fetch the missing ones by name.
  final named = {
    ...?allowlist,
    ...?overrides?.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key),
  }..removeWhere(
    (name) =>
        overrides?[name] == false || candidates.any((run) => run.name == name),
  );
  if (named.isNotEmpty) {
    final byName = {
      'name': {r'$in': named.toList()},
    };
    await collect(
      tabFilters == null
          ? byName
          : {
            r'$and': [tabFilters, byName],
          },
      1,
    );
  }
  return (
    candidates: candidates,
    visible: visible,
    limit: limit,
    totalCount: totalCount,
  );
});

/// Reloads one panel. The shared run listing is retried too when it is what
/// failed; always re-listing would re-page runs on every 30-second poll.
void refreshPanelSeries(WidgetRef ref, PanelRequest request) {
  if (request.runName == null &&
      ref.read(visibleRunsProvider(request.project)).hasError) {
    ref.invalidate(visibleRunsProvider(request.project));
  }
  ref.invalidate(panelSeriesProvider(request));
}

final panelSeriesProvider = FutureProvider.autoDispose.family<
  List<MetricSeries>,
  PanelRequest
>((ref, request) async {
  ref.watch(
    panelRefreshProvider((project: request.project, runName: request.runName)),
  );
  final repository = ref.watch(runsRepositoryProvider);
  // A rebuild disposes this build while it may still be awaiting; stop early
  // so a superseded build does not fetch histories the new one refetches.
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final workspace = await ref.watch(
    workspaceSettingsProvider(request.project).future,
  );
  if (disposed) return const [];
  final scope =
      request.runName == null
          ? request.project.path
          : '${request.project.path}/${request.runName}';
  // The server shapes the data along the chosen axis and aggregation, so only
  // those two settings (not smoothing or range edits) refetch.
  final (xAxis, aggregation) = ref.watch(
    mobilePreferencesProvider.select((value) {
      final rule = value.ruleFor(scope, request.metric, workspace);
      return (rule.xAxis, rule.pointAggregation);
    }),
  );
  Future<List<MetricSeries>> fetch(String runName) =>
      aggregation == 'sampling'
          ? repository.getSampledHistory(
            entity: request.project.entity,
            project: request.project.project,
            runName: runName,
            keys: [request.metric],
            xAxis: xAxis,
          )
          : repository.getBucketedHistory(
            entity: request.project.entity,
            project: request.project.project,
            runName: runName,
            keys: [request.metric],
            xAxis: xAxis,
          );
  if (request.runName != null) return fetch(request.runName!);
  final runs = await ref.watch(visibleRunsProvider(request.project).future);
  if (disposed) return const [];
  final lines = <MetricSeries>[];
  for (var start = 0; start < runs.visible.length; start += 6) {
    final end = (start + 6).clamp(0, runs.visible.length);
    final batch = await Future.wait(
      runs.visible.sublist(start, end).map((run) async {
        final history = await fetch(run.name);
        return MetricSeries(
          key: '${run.displayName} (${run.name})',
          points: history.firstOrNull?.points ?? [],
        );
      }),
    );
    if (disposed) return lines;
    lines.addAll(batch.where((line) => !line.isEmpty));
  }
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
