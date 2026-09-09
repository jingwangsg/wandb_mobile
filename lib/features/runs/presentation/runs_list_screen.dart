import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/resource_refs.dart';
import '../../../core/widgets/mobile_controls.dart';
import '../../../core/widgets/wandb_icon.dart';
import '../../charts/presentation/panels_view.dart';
import '../../aria/data/aria_repository.dart';
import '../../notifications/presentation/metric_alert_sheet.dart';
import '../providers/runs_providers.dart';
import 'recent_runs_screen.dart';
import 'widgets/run_filter_sheet.dart';

class RunsListScreen extends ConsumerStatefulWidget {
  const RunsListScreen({
    super.key,
    required this.entity,
    required this.project,
  });
  final String entity;
  final String project;
  @override
  ConsumerState<RunsListScreen> createState() => _RunsListScreenState();
}

class _RunsListScreenState extends ConsumerState<RunsListScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  Timer? _poll;
  Timer? _debounce;
  late final TextEditingController _search;
  ProjectRef get _project =>
      ProjectRef(entity: widget.entity, project: widget.project);

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(runFiltersProvider(_project)).searchQuery ?? '',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        ref.read(ariaProjectContextProvider.notifier).state = _project;
    });
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        ref.read(runsProvider(_project).notifier).refreshRetainingPages();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _poll?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      runFiltersProvider(_project).select((filters) => filters.searchQuery),
      (_, value) {
        final text = value ?? '';
        if (_search.text != text) {
          _debounce?.cancel();
          _search.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        }
      },
    );
    final runs = ref.watch(runsProvider(_project));
    final filters = ref.watch(runFiltersProvider(_project));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.project,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const WandbIcon('overflow_(horizontal)'),
            itemBuilder:
                (_) => const [
                  PopupMenuItem(
                    value: 'alert',
                    child: Text('Run failed alert'),
                  ),
                  PopupMenuItem(
                    value: '-created_at',
                    child: Text('Newest first'),
                  ),
                  PopupMenuItem(
                    value: '+created_at',
                    child: Text('Oldest first'),
                  ),
                  PopupMenuItem(
                    value: '-heartbeat_at',
                    child: Text('Recently active'),
                  ),
                ],
            onSelected: (value) {
              if (value == 'alert') {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => MetricAlertSheet(project: _project),
                );
              } else {
                ref.read(runFiltersProvider(_project).notifier).setOrder(value);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [Tab(text: 'Runs'), Tab(text: 'Panels')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _search,
                              decoration: const InputDecoration(
                                hintText: 'Search runs',
                                prefixIcon: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: WandbIcon('search'),
                                ),
                              ),
                              onChanged: (value) {
                                _debounce?.cancel();
                                _debounce = Timer(
                                  const Duration(milliseconds: 300),
                                  () {
                                    if (mounted) {
                                      ref
                                          .read(
                                            runFiltersProvider(
                                              _project,
                                            ).notifier,
                                          )
                                          .setSearchQuery(value);
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: 'Filter runs',
                            icon: Badge(
                              isLabelVisible: filters.hasAdvancedFilters,
                              label: Text(
                                filters.advancedFilterCount.toString(),
                              ),
                              child: const WandbIcon('settings_parameters'),
                            ),
                            onPressed:
                                () => showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder:
                                      (_) =>
                                          RunFilterSheet(projectRef: _project),
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (filters.searchQuery?.isNotEmpty == true ||
                        filters.hasAdvancedFilters)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (filters.searchQuery?.isNotEmpty == true)
                              InputChip(
                                label: Text('Search: ${filters.searchQuery}'),
                                onDeleted: () {
                                  _debounce?.cancel();
                                  _search.clear();
                                  ref
                                      .read(
                                        runFiltersProvider(_project).notifier,
                                      )
                                      .clearSearchQuery();
                                },
                              ),
                            if (filters.hasAdvancedFilters)
                              InputChip(
                                label: Text(
                                  '${filters.advancedFilterCount} filters',
                                ),
                                onDeleted:
                                    () =>
                                        ref
                                            .read(
                                              runFiltersProvider(
                                                _project,
                                              ).notifier,
                                            )
                                            .clearAdvancedFilter(),
                              ),
                          ],
                        ),
                      ),
                    if (runs.isRefreshing)
                      const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: runs.when(
                        loading:
                            () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                        error:
                            (error, _) => MobileEmptyState(
                              title: 'Unable to load runs',
                              message: '$error',
                              icon: 'warning',
                              onRetry:
                                  () =>
                                      ref
                                          .read(runsProvider(_project).notifier)
                                          .refresh(),
                            ),
                        data:
                            (page) => RefreshIndicator(
                              onRefresh:
                                  () =>
                                      ref
                                          .read(runsProvider(_project).notifier)
                                          .refresh(),
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (notice) {
                                  if (notice.metrics.extentAfter < 200 &&
                                      page.hasNextPage) {
                                    ref
                                        .read(runsProvider(_project).notifier)
                                        .loadMore();
                                  }
                                  return false;
                                },
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    24,
                                  ),
                                  itemCount: page.items.length + 1,
                                  itemBuilder: (context, index) {
                                    if (index == page.items.length) {
                                      if (page.hasNextPage) {
                                        return TextButton(
                                          onPressed:
                                              () =>
                                                  ref
                                                      .read(
                                                        runsProvider(
                                                          _project,
                                                        ).notifier,
                                                      )
                                                      .loadMore(),
                                          child: const Text('Load more'),
                                        );
                                      }
                                      return page.items.isEmpty
                                          ? const Padding(
                                            padding: EdgeInsets.only(top: 64),
                                            child: MobileEmptyState(
                                              title: 'No runs found',
                                              icon: 'triangle_(right)',
                                            ),
                                          )
                                          : const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: RunCard(
                                        run: page.items[index],
                                        project: _project,
                                        showVisibility: true,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
                PanelsView(project: _project, visible: _tabs.index == 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
