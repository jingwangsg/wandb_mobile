import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/paginated.dart';
import '../../../core/models/run.dart';
import '../../../core/models/resource_refs.dart';
import '../../../core/providers/paginated_async_notifier.dart';
import '../../../core/providers/mobile_preferences.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/mobile_controls.dart';
import '../../../core/widgets/wandb_icon.dart';
import '../../charts/providers/panel_providers.dart';
import '../../charts/presentation/widgets/wandb_line_chart.dart';
import '../data/runs_repository.dart';
import '../providers/runs_providers.dart';
import '../utils/metric_selection.dart';

class RecentRunsNotifier extends PaginatedAsyncNotifier<WandbRun> {
  RecentRunsNotifier(this._repo, this._pattern) {
    load();
  }
  final RunsRepository _repo;
  final String _pattern;
  @override
  Future<PaginatedResult<WandbRun>> loadPage({String? cursor}) =>
      _repo.getRecentRuns(
        cursor: cursor,
        pattern: _pattern.isEmpty ? null : _pattern,
      );
}

final recentRunsProvider = StateNotifierProvider.autoDispose
    .family<RecentRunsNotifier, AsyncValue<PaginatedResult<WandbRun>>, String>(
      (ref, pattern) =>
          RecentRunsNotifier(ref.watch(runsRepositoryProvider), pattern),
    );

class RecentRunsScreen extends ConsumerStatefulWidget {
  const RecentRunsScreen({super.key});
  @override
  ConsumerState<RecentRunsScreen> createState() => _RecentRunsScreenState();
}

class _RecentRunsScreenState extends ConsumerState<RecentRunsScreen> {
  String _pattern = '';
  Timer? _debounce;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          TickerMode.valuesOf(context).enabled &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        ref.read(recentRunsProvider(_pattern).notifier).refreshRetainingPages();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runs = ref.watch(recentRunsProvider(_pattern));
    return Scaffold(
      appBar: AppBar(title: const Text('Your runs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search runs',
                prefixIcon: Padding(
                  padding: EdgeInsets.all(12),
                  child: WandbIcon('search'),
                ),
              ),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() => _pattern = value.trim());
                });
              },
            ),
          ),
          if (runs.isRefreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: runs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (error, _) => MobileEmptyState(
                    title: 'Unable to load runs',
                    message: '$error',
                    icon: 'warning',
                    onRetry:
                        () =>
                            ref
                                .read(recentRunsProvider(_pattern).notifier)
                                .refresh(),
                  ),
              data:
                  (page) => RefreshIndicator(
                    onRefresh:
                        () =>
                            ref
                                .read(recentRunsProvider(_pattern).notifier)
                                .refresh(),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: page.items.length + 1,
                      itemBuilder: (context, index) {
                        if (index == page.items.length) {
                          if (page.hasNextPage) {
                            return TextButton(
                              onPressed:
                                  () =>
                                      ref
                                          .read(
                                            recentRunsProvider(
                                              _pattern,
                                            ).notifier,
                                          )
                                          .loadMore(),
                              child: const Text('Load more'),
                            );
                          }
                          if (page.items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 64),
                              child: MobileEmptyState(
                                title: 'No runs found',
                                message: 'Your training runs will appear here.',
                                icon: 'triangle_(right)',
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }
                        final run = page.items[index];
                        final project = ProjectRef(
                          entity: run.entityName!,
                          project: run.projectName!,
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RunCard(
                            run: run,
                            project: project,
                            showProject: true,
                          ),
                        );
                      },
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class RunCard extends ConsumerWidget {
  const RunCard({
    super.key,
    required this.run,
    required this.project,
    this.showProject = false,
    this.showVisibility = false,
  });
  final WandbRun run;
  final ProjectRef project;
  final bool showProject;
  final bool showVisibility;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(mobilePreferencesProvider);
    final hidden =
        preferences.hiddenRuns[project.path]?.contains(run.name) == true;
    final history = run.historyKeys?['keys'] as Map? ?? {};
    final available =
        <String>{
          ...history.keys.cast<String>(),
          ...run.summaryMetrics.entries
              .where((entry) => entry.value is num)
              .map((entry) => entry.key),
        }.where((key) => !key.startsWith('_') && !isSystemMetric(key)).toList();
    final starred = available.where(
      (key) => isMetricStarred(preferences, project, key),
    );
    final metric =
        starred.firstOrNull ??
        defaultMetricKeys(
          available,
          history.cast<String, dynamic>(),
        ).firstOrNull;
    final preview =
        metric == null
            ? null
            : ref.watch(
              panelSeriesProvider((
                project: project,
                runName: run.name,
                metric: metric,
              )),
            );
    final stateColor = WandbColors.forRunState(run.state.name);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap:
            () => context.push(
              '/projects/${Uri.encodeComponent(project.entity)}/${Uri.encodeComponent(project.project)}/runs/${Uri.encodeComponent(run.name)}',
              extra: run,
            ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showProject)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    project.path,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: stateColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      run.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (showVisibility)
                    IconButton(
                      tooltip:
                          hidden
                              ? 'Show run in panels'
                              : 'Hide run from panels',
                      onPressed:
                          () => ref
                              .read(mobilePreferencesProvider.notifier)
                              .toggleRun(project.path, run.name),
                      icon: WandbIcon(
                        hidden ? 'not_visible' : 'visible',
                        size: 20,
                      ),
                    ),
                  const WandbIcon('chevron_(next)', size: 16),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${run.state.name[0].toUpperCase()}${run.state.name.substring(1)} · ${formatRelativeTime(run.createdAt)}${run.duration == null ? '' : ' · ${formatDuration(run.duration!)}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (preview != null)
                SizedBox(
                  height: 112,
                  child: preview.when(
                    loading:
                        () => const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ),
                    error:
                        (_, _) =>
                            const Center(child: Text('Error loading preview')),
                    data:
                        (lines) =>
                            lines.every((line) => line.isEmpty)
                                ? const SizedBox.shrink()
                                : IgnorePointer(
                                  child: WandbLineChart(
                                    series: lines,
                                    showLegend: false,
                                  ),
                                ),
                  ),
                ),
              if (metric != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    metric,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
