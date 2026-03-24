import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/paginated.dart';
import '../../../core/models/resource_refs.dart';
import '../../../core/models/run.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/responsive.dart';
import '../providers/runs_providers.dart';
import 'run_detail_screen.dart';
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

class _RunsListScreenState extends ConsumerState<RunsListScreen> {
  ProjectRef get _projectRef =>
      ProjectRef(entity: widget.entity, project: widget.project);

  /// Selected run for wide-screen detail panel.
  WandbRun? _selectedRun;

  @override
  Widget build(BuildContext context) {
    final runsAsync = ref.watch(runsProvider(_projectRef));
    final filters = ref.watch(runFiltersProvider(_projectRef));

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = !isCompact(constraints.maxWidth);

        final listPanel = _RunsListPanel(
          runsAsync: runsAsync,
          filters: filters,
          selectedRunName: _selectedRun?.name,
          onRunTap: (run) {
            if (wide) {
              setState(() => _selectedRun = run);
            } else {
              context.push(
                '/projects/${widget.entity}/${widget.project}/runs/${run.name}',
                extra: run,
              );
            }
          },
          onSearchChanged: (v) {
            ref
                .read(runFiltersProvider(_projectRef).notifier)
                .setSearchQuery(v);
          },
          onClearSearch: () {
            ref
                .read(runFiltersProvider(_projectRef).notifier)
                .clearSearchQuery();
          },
          onClearAdvancedFilter: () {
            ref
                .read(runFiltersProvider(_projectRef).notifier)
                .clearAdvancedFilter();
          },
          onRefresh:
              () => ref.read(runsProvider(_projectRef).notifier).refresh(),
          onLoadMore:
              () => ref.read(runsProvider(_projectRef).notifier).loadMore(),
          onRetry:
              () => ref.read(runsProvider(_projectRef).notifier).refresh(),
        );

        if (!wide) {
          return Scaffold(appBar: _buildAppBar(filters), body: listPanel);
        }

        // Wide: master-detail split
        return Scaffold(
          appBar: _buildAppBar(filters),
          body: Row(
            children: [
              // Master: run list
              SizedBox(width: constraints.maxWidth * 0.38, child: listPanel),
              const VerticalDivider(width: 1, thickness: 1),
              // Detail: selected run
              Expanded(
                child:
                    _selectedRun != null
                        ? RunDetailScreen(
                          key: ValueKey(_selectedRun!.name),
                          entity: widget.entity,
                          project: widget.project,
                          runName: _selectedRun!.name,
                          run: _selectedRun,
                          embedded: true,
                        )
                        : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.touch_app,
                                size: 48,
                                color: Colors.white24,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Select a run to view details',
                                style: TextStyle(color: Colors.white38),
                              ),
                            ],
                          ),
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(RunFilters filters) {
    return AppBar(
      title: Text(widget.project),
      actions: [
        IconButton(
          icon: Badge(
            isLabelVisible: filters.hasAdvancedFilters,
            label: Text(filters.advancedFilterCount.toString()),
            child: const Icon(Icons.filter_list),
          ),
          onPressed: () => _showFilters(context, ref),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          onSelected: (order) {
            ref.read(runFiltersProvider(_projectRef).notifier).setOrder(order);
          },
          itemBuilder:
              (_) => const [
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
        ),
      ],
    );
  }

  void _showFilters(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RunFilterSheet(projectRef: _projectRef),
    );
  }
}

/// Extracted list panel — used in both narrow (full screen) and wide (left panel).
class _RunsListPanel extends StatelessWidget {
  const _RunsListPanel({
    required this.runsAsync,
    required this.filters,
    required this.onRunTap,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onClearAdvancedFilter,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onRetry,
    this.selectedRunName,
  });

  final AsyncValue<PaginatedResult<WandbRun>> runsAsync;
  final RunFilters filters;
  final String? selectedRunName;
  final void Function(WandbRun) onRunTap;
  final void Function(String) onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onClearAdvancedFilter;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _RunSearchField(
            value: filters.searchQuery ?? '',
            onChanged: onSearchChanged,
          ),
        ),

        // Active filter chips
        if (filters.hasSearchQuery || filters.hasAdvancedFilters)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (filters.hasSearchQuery)
                  Chip(
                    label: Text('Search: ${filters.normalizedSearchQuery}'),
                    onDeleted: onClearSearch,
                    deleteIcon: const Icon(Icons.close, size: 16),
                  ),
                if (filters.hasAdvancedFilters)
                  Chip(
                    label: Text(
                      filters.advancedFilterCount == 1
                          ? '1 filter'
                          : '${filters.advancedFilterCount} filters',
                    ),
                    onDeleted: onClearAdvancedFilter,
                    deleteIcon: const Icon(Icons.close, size: 16),
                  ),
              ],
            ),
          ),

        // Runs list
        Expanded(
          child: runsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Error: $e'),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
            data: (result) {
              if (result.items.isEmpty) {
                return const Center(child: Text('No runs found'));
              }

              return RefreshIndicator(
                onRefresh: onRefresh,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: result.items.length + (result.hasNextPage ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == result.items.length) {
                      onLoadMore();
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final run = result.items[index];
                    final isSelected = run.name == selectedRunName;
                    return _RunTile(
                      run: run,
                      selected: isSelected,
                      onTap: () => onRunTap(run),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RunSearchField extends StatefulWidget {
  const _RunSearchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_RunSearchField> createState() => _RunSearchFieldState();
}

class _RunSearchFieldState extends State<_RunSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _RunSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _controller.text) return;
    _controller.value = TextEditingValue(
      text: widget.value,
      selection: TextSelection.collapsed(offset: widget.value.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      decoration: const InputDecoration(
        hintText: 'Search runs...',
        prefixIcon: Icon(Icons.search),
        isDense: true,
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run, this.onTap, this.selected = false});

  final WandbRun run;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final stateColor = WandbColors.forRunState(run.state.name);

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color:
          selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: stateColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),

              // Run info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      run.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: stateColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            run.state.name,
                            style: TextStyle(
                              color: stateColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (run.tags.isNotEmpty)
                          Flexible(
                            child: Text(
                              run.tags.take(2).join(', '),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white38,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                    if (run.summaryMetrics.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        _formatTopMetrics(run.summaryMetrics),
                        style: Theme.of(context).textTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRelativeTime(run.createdAt),
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                  if (run.duration != null)
                    Text(
                      formatDuration(run.duration!),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white24,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTopMetrics(Map<String, dynamic> metrics) {
    final entries = metrics.entries
        .where((e) => !e.key.startsWith('_'))
        .take(3);
    return entries
        .map((e) => '${e.key}: ${formatMetricValue(e.value)}')
        .join('  ');
  }
}
