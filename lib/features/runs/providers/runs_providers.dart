import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/resource_refs.dart';
import '../../../core/models/metric_point.dart';
import '../../../core/models/paginated.dart';
import '../../../core/models/run.dart';
import '../../../core/providers/paginated_async_notifier.dart';
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
    StateNotifierProvider.family<RunFiltersNotifier, RunFilters, ProjectRef>((
      ref,
      projectRef,
    ) {
      return RunFiltersNotifier();
    });

// ─── Runs List ───────────────────────────────────────────

class RunsListNotifier extends PaginatedAsyncNotifier<WandbRun> {
  RunsListNotifier(this._repo, this._entity, this._project, this._filters)
    : super() {
    load();
  }

  final RunsRepository _repo;
  final String _entity;
  final String _project;
  final RunFilters _filters;

  @override
  Future<PaginatedResult<WandbRun>> loadPage({String? cursor}) {
    return _repo.getRuns(
      entity: _entity,
      project: _project,
      cursor: cursor,
      order: _filters.order,
      filters: _filters.toApiFilters(),
    );
  }
}

final runsProvider = StateNotifierProvider.family<
  RunsListNotifier,
  AsyncValue<PaginatedResult<WandbRun>>,
  ProjectRef
>((ref, projectRef) {
  final repo = ref.watch(runsRepositoryProvider);
  final filters = ref.watch(runFiltersProvider(projectRef));
  return RunsListNotifier(
    repo,
    projectRef.entity,
    projectRef.project,
    filters,
  );
});

// ─── Sampled History (for charts) ────────────────────────

final sampledHistoryProvider = FutureProvider.family<
  List<MetricSeries>,
  ({RunRef runRef, List<String> keys})
>((ref, params) async {
  final repo = ref.watch(runsRepositoryProvider);
  return repo.getSampledHistory(
    entity: params.runRef.entity,
    project: params.runRef.project,
    runName: params.runRef.runName,
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
