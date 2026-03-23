import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/metric_point.dart';
import '../../../core/models/paginated.dart';
import '../../../core/models/run.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/runs_repository.dart';
import '../models/run_filters.dart';

export '../models/run_filters.dart';

final runsRepositoryProvider = Provider<RunsRepository>((ref) {
  final client = ref.watch(graphqlClientProvider);
  return RunsRepository(client);
});

// ─── Run Filters & Sort ──────────────────────────────────

class RunFiltersNotifier extends StateNotifier<RunFilters> {
  RunFiltersNotifier() : super(const RunFilters());

  void setOrder(String order) {
    state = state.copyWith(order: order);
  }

  void setSearchQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearSearchQuery();
      return;
    }
    state = state.copyWith(searchQuery: trimmed);
  }

  void clearSearchQuery() {
    state = state.copyWith(clearSearchQuery: true);
  }

  void applyAdvancedFilter(RunFilterGroup root) {
    if (root.children.isNotEmpty && !root.isValid) return;
    state = state.copyWith(
      advancedFilterRoot: root.children.isEmpty ? null : root,
      clearAdvancedFilter: root.children.isEmpty,
    );
  }

  void clearAdvancedFilter() {
    state = state.copyWith(clearAdvancedFilter: true);
  }

  void clearAll() {
    state = const RunFilters();
  }
}

final runFiltersProvider =
    StateNotifierProvider.family<RunFiltersNotifier, RunFilters, String>((
      ref,
      projectPath,
    ) {
      return RunFiltersNotifier();
    });

// ─── Runs List ───────────────────────────────────────────

class RunsListNotifier
    extends StateNotifier<AsyncValue<PaginatedResult<WandbRun>>> {
  RunsListNotifier(this._repo, this._entity, this._project, this._filters)
    : super(const AsyncValue.loading()) {
    load();
  }

  final RunsRepository _repo;
  final String _entity;
  final String _project;
  final RunFilters _filters;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final result = await _repo.getRuns(
        entity: _entity,
        project: _project,
        order: _filters.order,
        filters: _filters.toApiFilters(),
      );
      state = AsyncValue.data(result);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasNextPage) return;

    try {
      final next = await _repo.getRuns(
        entity: _entity,
        project: _project,
        cursor: current.endCursor,
        order: _filters.order,
        filters: _filters.toApiFilters(),
      );
      state = AsyncValue.data(current.appendPage(next));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => load();
}

/// Provider key: "entity/project"
final runsProvider = StateNotifierProvider.family<
  RunsListNotifier,
  AsyncValue<PaginatedResult<WandbRun>>,
  String
>((ref, projectPath) {
  final parts = projectPath.split('/');
  final entity = parts[0];
  final project = parts[1];
  final repo = ref.watch(runsRepositoryProvider);
  final filters = ref.watch(runFiltersProvider(projectPath));
  return RunsListNotifier(repo, entity, project, filters);
});

// ─── Sampled History (for charts) ────────────────────────

/// Key: "entity/project/runName"
final sampledHistoryProvider = FutureProvider.family<
  List<MetricSeries>,
  ({String entity, String project, String runName, List<String> keys})
>((ref, params) async {
  final repo = ref.watch(runsRepositoryProvider);
  return repo.getSampledHistory(
    entity: params.entity,
    project: params.project,
    runName: params.runName,
    keys: params.keys,
  );
});

// ─── Auto-polling for running runs ───────────────────────

class RunPollingNotifier extends StateNotifier<AsyncValue<WandbRun>> {
  RunPollingNotifier(
    this._repo,
    this._entity,
    this._project,
    this._run, {
    Duration pollInterval = const Duration(seconds: 30),
  }) : super(AsyncValue.data(_run)) {
    if (_run.state.isActive) {
      _timer = Timer.periodic(pollInterval, (_) => _poll());
    }
  }

  final RunsRepository _repo;
  final String _entity;
  final String _project;
  final WandbRun _run;
  Timer? _timer;

  Future<void> _poll() async {
    try {
      final result = await _repo.getRuns(
        entity: _entity,
        project: _project,
        filters: {'name': _run.name},
        perPage: 1,
      );
      if (result.items.isNotEmpty) {
        final updated = result.items.first;
        state = AsyncValue.data(updated);
        // Stop polling if run reached terminal state
        if (updated.state.isTerminal) {
          _timer?.cancel();
          _timer = null;
        }
      }
    } catch (_) {
      // Silently ignore poll errors
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
