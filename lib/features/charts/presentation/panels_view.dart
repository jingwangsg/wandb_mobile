import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/metric_point.dart';
import '../../../core/models/resource_refs.dart';
import '../../../core/models/run.dart';
import '../../../core/providers/mobile_preferences.dart';
import '../../../core/theme/colors.dart';
import '../../../core/widgets/mobile_controls.dart';
import '../../../core/widgets/wandb_icon.dart';
import '../../notifications/presentation/metric_alert_sheet.dart';
import '../../runs/utils/metric_selection.dart';
import '../models/metric_chart_rule.dart';
import '../models/panel_spec.dart';
import '../models/run_grouping.dart';
import '../providers/panel_providers.dart';
import 'widgets/grouping_sheet.dart';
import 'widgets/image_metric_panel.dart';
import 'widgets/key_picker.dart';
import 'widgets/line_plot_settings.dart';
import 'widgets/panel_editor_sheet.dart';
import 'widgets/visible_runs_sheet.dart';
import 'widgets/wandb_line_chart.dart';

class PanelsView extends ConsumerStatefulWidget {
  const PanelsView({
    super.key,
    required this.project,
    this.run,
    this.visible = true,
  });
  final ProjectRef project;
  final WandbRun? run;
  final bool visible;

  @override
  ConsumerState<PanelsView> createState() => _PanelsViewState();
}

class _PanelsViewState extends ConsumerState<PanelsView> {
  bool _starredOnly = false;
  String _query = '';
  RegExp? _pattern;
  String? _searchError;
  final _collapsed = <String>{};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          widget.visible &&
          (widget.run == null || widget.run!.state.isActive) &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        final catalog =
            widget.run == null
                ? ref.read(projectMetricKeysProvider(widget.project))
                : null;
        if (catalog?.isLoading == true) return;
        final metrics =
            catalog?.valueOrNull ??
            (widget.run?.historyKeys?['keys'] as Map? ?? {}).keys
                .cast<String>();
        for (final metric in metrics) {
          final provider = panelSeriesProvider((
            project: widget.project,
            runName: widget.run?.name,
            panel: PanelSpec.metric(metric),
          ));
          if (ref.exists(provider) && ref.read(provider).isLoading) return;
        }
        ref
            .read(
              panelRefreshProvider((
                project: widget.project,
                runName: widget.run?.name,
              )).notifier,
            )
            .state++;
        ref.invalidate(projectMetricKeysProvider(widget.project));
        if (widget.run != null) {
          ref.invalidate(
            runSystemSeriesProvider(
              RunRef(
                entity: widget.project.entity,
                project: widget.project.project,
                runName: widget.run!.name,
              ),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Opens the app panel editor: a new panel, or [initial] to edit or delete.
  void _editPanel(String scope, List<String> catalog, [PanelSpec? initial]) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder:
            (_) => PanelEditorSheet(
              initial: initial,
              catalog: catalog,
              onSave:
                  (panel) => ref
                      .read(mobilePreferencesProvider.notifier)
                      .setCustomPanel(scope, panel),
              onDelete:
                  initial == null
                      ? null
                      : () => ref
                          .read(mobilePreferencesProvider.notifier)
                          .removeCustomPanel(scope, initial.id),
            ),
      );

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(mobilePreferencesProvider);
    final visibleRuns =
        widget.run == null
            ? ref.watch(visibleRunsProvider(widget.project)).valueOrNull
            : null;
    final workspace =
        ref.watch(workspaceSettingsProvider(widget.project)).valueOrNull;
    final grouping =
        widget.run == null
            ? groupingKeys(preferences.grouping, workspace, widget.project.path)
            : const <String>[];
    final imageMetrics = <String>{};
    for (final entry
        in (widget.run?.historyKeys?['keys'] as Map? ?? {}).entries) {
      final types =
          entry.value is Map
              ? entry.value['typeCounts'] as List? ?? []
              : const [];
      if (types.any(
        (type) => type is Map && type['type'].toString().contains('image'),
      )) {
        imageMetrics.add(entry.key.toString());
      }
    }
    for (final entry
        in widget.run?.summaryMetrics.entries ??
            const <MapEntry<String, dynamic>>[]) {
      if (entry.value is Map &&
          entry.value['_type'].toString().contains('image')) {
        imageMetrics.add(entry.key);
      }
    }
    final scope =
        widget.run == null
            ? widget.project.path
            : '${widget.project.path}/${widget.run!.name}';
    final keys =
        widget.run == null
            ? ref.watch(projectMetricKeysProvider(widget.project))
            : AsyncValue.data(
              <String>{
                    ...imageMetrics,
                    ...?(widget.run!.historyKeys?['keys'] as Map?)?.keys
                        .cast<String>(),
                    ...widget.run!.summaryMetrics.entries
                        .where((entry) => entry.value is num)
                        .map((entry) => entry.key),
                  }
                  .where((key) => !key.startsWith('_') && !isSystemMetric(key))
                  .toList(),
            );
    final system =
        widget.run == null
            ? const AsyncValue<List<MetricSeries>>.data([])
            : ref.watch(
              runSystemSeriesProvider(
                RunRef(
                  entity: widget.project.entity,
                  project: widget.project.project,
                  runName: widget.run!.name,
                ),
              ),
            );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: StarFilter(
                  starredOnly: _starredOnly,
                  onChanged: (value) => setState(() => _starredOnly = value),
                ),
              ),
              if (widget.run == null)
                TextButton.icon(
                  onPressed:
                      () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder:
                            (_) => VisibleRunsSheet(project: widget.project),
                      ),
                  icon: const WandbIcon('visible', size: 18),
                  label: Text(
                    visibleRuns == null
                        ? 'Runs'
                        : '${visibleRuns.visible.length} of '
                            '${visibleRuns.totalCount ?? visibleRuns.candidates.length} runs',
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'Panel options',
                icon: const WandbIcon('settings_parameters'),
                itemBuilder:
                    (_) => [
                      const PopupMenuItem(
                        value: 'settings',
                        child: Text('Line plot settings'),
                      ),
                      const PopupMenuItem(
                        value: 'add',
                        child: Text('Add panel'),
                      ),
                      if (widget.run == null)
                        PopupMenuItem(
                          value: 'group',
                          child: Text(
                            grouping.isEmpty
                                ? 'Group runs'
                                : 'Group runs (${grouping.length})',
                          ),
                        ),
                    ],
                onSelected: (value) {
                  if (value == 'add') {
                    _editPanel(scope, keys.valueOrNull ?? const []);
                    return;
                  }
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder:
                        (_) =>
                            value == 'group'
                                ? GroupingSheet(project: widget.project)
                                : LinePlotSettings(
                                  rule: preferences.scopeRuleFor(
                                    scope,
                                    workspace,
                                  ),
                                  resetRule:
                                      workspace?.workspaceDefaults ??
                                      MetricChartRule.defaults,
                                  scope:
                                      widget.run == null
                                          ? 'Applies to all line plots in this project'
                                          : 'Applies to all line plots in this run',
                                  xAxisOptions: keys.valueOrNull ?? const [],
                                  grouped: grouping.isNotEmpty,
                                  onChanged:
                                      (rule) => ref
                                          .read(
                                            mobilePreferencesProvider.notifier,
                                          )
                                          .setDefaults(scope, rule),
                                  onReset:
                                      () => ref
                                          .read(
                                            mobilePreferencesProvider.notifier,
                                          )
                                          .resetDefaults(scope),
                                ),
                  );
                },
              ),
            ],
          ),
        ),
        // One legend for the page: every panel colours runs (or groups, when
        // grouping is on) by this order, so the colours match across cards.
        if (visibleRuns != null && visibleRuns.visible.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                for (final (index, (label, color))
                    in <(String, int?)>[
                      if (grouping.isEmpty)
                        for (final run in visibleRuns.visible)
                          (run.displayName, workspace?.runColors[run.name])
                      else
                        for (final label in {
                          for (final run in visibleRuns.visible)
                            groupLabel(run, grouping),
                        })
                          (label, null),
                    ].indexed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color:
                              color != null
                                  ? Color(color)
                                  : WandbColors.seriesColor(index),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(label, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
              ],
            ),
          ),
        Expanded(
          child: keys.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (error, _) => MobileEmptyState(
                  title: 'Unable to load panels',
                  message: '$error',
                  icon: 'warning',
                  onRetry:
                      () => ref.invalidate(
                        projectMetricKeysProvider(widget.project),
                      ),
                ),
            data: (names) {
              final historyKeys = Map<String, dynamic>.from(
                widget.run?.historyKeys?['keys'] as Map? ?? {},
              );
              final rankedNames = [...names]..sort((a, b) {
                final priority = metricPriorityScore(
                  b,
                  historyKeys,
                ).compareTo(metricPriorityScore(a, historyKeys));
                return priority != 0 ? priority : a.compareTo(b);
              });
              // App panels first, then the web's explicit panels by their
              // section, then one auto panel per metric (minus those hidden
              // on the web).
              final appPanels = preferences.customPanels[scope] ?? const [];
              // Metrics the web already saved a panel for keep that panel.
              final webPanelIds = {
                for (final panel in workspace?.panels ?? const <PanelSpec>[])
                  panel.id,
              };
              final groups = <String, List<PanelSpec>>{};
              for (final panel in [
                ...appPanels,
                ...?workspace?.panels,
                for (final name in rankedNames)
                  if (workspace?.hiddenMetrics.contains(name) != true &&
                      !webPanelIds.contains(name))
                    PanelSpec.metric(name),
              ]) {
                if (_starredOnly &&
                    !isMetricStarred(preferences, widget.project, panel.id)) {
                  continue;
                }
                if (_pattern != null &&
                    !_pattern!.hasMatch(panel.displayTitle)) {
                  continue;
                }
                (groups[panel.section] ??= []).add(panel);
              }
              final systemLines =
                  system.valueOrNull
                      ?.where(
                        (line) =>
                            (!_starredOnly ||
                                isMetricStarred(
                                  preferences,
                                  widget.project,
                                  line.key,
                                )) &&
                            (_pattern == null || _pattern!.hasMatch(line.key)),
                      )
                      .toList() ??
                  [];
              final sections = groups.keys.toList();
              return RefreshIndicator(
                onRefresh: () async {
                  ref
                      .read(
                        panelRefreshProvider((
                          project: widget.project,
                          runName: widget.run?.name,
                        )).notifier,
                      )
                      .state++;
                  ref.invalidate(projectMetricKeysProvider(widget.project));
                  ref.invalidate(workspaceSettingsProvider(widget.project));
                  if (widget.run != null) {
                    ref.invalidate(
                      runSystemSeriesProvider(
                        RunRef(
                          entity: widget.project.entity,
                          project: widget.project.project,
                          runName: widget.run!.name,
                        ),
                      ),
                    );
                  }
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (groups.isEmpty &&
                        systemLines.isEmpty &&
                        !system.isLoading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: MobileEmptyState(
                          title: 'No matching panels',
                          message: 'Try another search or select All.',
                          icon: 'chart_(line)',
                        ),
                      ),
                    for (final section in sections) ...[
                      SliverToBoxAdapter(
                        child: ListTile(
                          title: Text(
                            section,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          trailing: WandbIcon(
                            _collapsed.contains(section)
                                ? 'chevron_(next)'
                                : 'chevron_(down)',
                            size: 18,
                          ),
                          onTap:
                              () => setState(() {
                                if (!_collapsed.remove(section)) {
                                  _collapsed.add(section);
                                }
                              }),
                        ),
                      ),
                      if (!_collapsed.contains(section))
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList.builder(
                            itemCount: groups[section]!.length,
                            itemBuilder: (context, index) {
                              final panel = groups[section]![index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child:
                                    widget.run != null &&
                                            panel.isAuto &&
                                            imageMetrics.contains(panel.id)
                                        ? ImageMetricPanel(
                                          run: RunRef(
                                            entity: widget.project.entity,
                                            project: widget.project.project,
                                            runName: widget.run!.name,
                                          ),
                                          metric: panel.id,
                                          lastStep:
                                              (widget.run!.historyKeys?['lastStep']
                                                          as num? ??
                                                      widget
                                                              .run!
                                                              .summaryMetrics['_step']
                                                          as num? ??
                                                      -1)
                                                  .toInt(),
                                        )
                                        : MetricPanelCard(
                                          project: widget.project,
                                          runName: widget.run?.name,
                                          panel: panel,
                                          onEdit:
                                              appPanels.contains(panel)
                                                  ? () => _editPanel(
                                                    scope,
                                                    keys.valueOrNull ??
                                                        const [],
                                                    panel,
                                                  )
                                                  : null,
                                        ),
                              );
                            },
                          ),
                        ),
                    ],
                    if (widget.run != null &&
                        (systemLines.isNotEmpty ||
                            system.isLoading ||
                            system.hasError)) ...[
                      SliverToBoxAdapter(
                        child: ListTile(
                          title: Text(
                            'System',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          trailing: WandbIcon(
                            _collapsed.contains('System')
                                ? 'chevron_(next)'
                                : 'chevron_(down)',
                            size: 18,
                          ),
                          onTap:
                              () => setState(() {
                                if (!_collapsed.remove('System')) {
                                  _collapsed.add('System');
                                }
                              }),
                        ),
                      ),
                      if (!_collapsed.contains('System')) ...[
                        if (system.isLoading)
                          const SliverToBoxAdapter(
                            child: LinearProgressIndicator(),
                          ),
                        if (system.hasError)
                          SliverToBoxAdapter(
                            child: ListTile(
                              title: const Text(
                                'Unable to load system metrics',
                              ),
                              trailing: TextButton(
                                onPressed:
                                    () => ref.invalidate(
                                      runSystemSeriesProvider(
                                        RunRef(
                                          entity: widget.project.entity,
                                          project: widget.project.project,
                                          runName: widget.run!.name,
                                        ),
                                      ),
                                    ),
                                child: const Text('Retry'),
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList.builder(
                            itemCount: systemLines.length,
                            itemBuilder:
                                (context, index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: MetricPanelCard(
                                    project: widget.project,
                                    runName: widget.run!.name,
                                    panel: PanelSpec.metric(
                                      systemLines[index].key,
                                    ),
                                    systemSeries: systemLines[index],
                                  ),
                                ),
                          ),
                        ),
                      ],
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search panels',
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: WandbIcon('search'),
                ),
                errorText: _searchError,
              ),
              onChanged:
                  (value) => setState(() {
                    _query = value;
                    try {
                      _pattern =
                          value.isEmpty
                              ? null
                              : RegExp(value, caseSensitive: false);
                      _searchError = null;
                    } on FormatException {
                      _searchError = 'Invalid regular expression';
                      _pattern = RegExp(
                        RegExp.escape(_query),
                        caseSensitive: false,
                      );
                    }
                  }),
            ),
          ),
        ),
      ],
    );
  }
}

class MetricPanelCard extends ConsumerWidget {
  const MetricPanelCard({
    super.key,
    required this.project,
    required this.panel,
    this.runName,
    this.systemSeries,
    this.onEdit,
  });
  final ProjectRef project;
  final PanelSpec panel;
  final String? runName;
  final MetricSeries? systemSeries;

  /// Set for panels created in the app; opens the editor.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(mobilePreferencesProvider);
    final starred = isMetricStarred(preferences, project, panel.id);
    final scope = runName == null ? project.path : '${project.path}/$runName';
    final workspace = ref.watch(workspaceSettingsProvider(project)).valueOrNull;
    final rule = preferences.ruleFor(scope, panel, workspace);
    final request = (project: project, runName: runName, panel: panel);
    final series =
        systemSeries == null
            ? ref.watch(panelSeriesProvider(request))
            : AsyncValue.data([systemSeries!]);
    void expand() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) =>
                PanelDetailScreen(request: request, systemSeries: systemSeries),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: expand,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 4,
                      ),
                      child: Text(
                        panel.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Edit panel',
                    onPressed: onEdit,
                    icon: const WandbIcon('pencil_(edit)', size: 18),
                  ),
                IconButton(
                  tooltip: starred ? 'Unstar panel' : 'Star panel',
                  onPressed:
                      () => ref
                          .read(mobilePreferencesProvider.notifier)
                          .toggleMetric(project.path, panel.id),
                  icon: WandbIcon(
                    starred ? 'star_(filled)' : 'star',
                    size: 20,
                    color:
                        starred
                            ? WandbColors.star
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  tooltip: 'Open panel',
                  onPressed: expand,
                  icon: const WandbIcon('chevron_(next)', size: 18),
                ),
              ],
            ),
            SizedBox(
              height: 165,
              child: series.when(
                loading:
                    () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                error:
                    (error, _) => Center(
                      child: TextButton(
                        onPressed: () => refreshPanelSeries(ref, request),
                        child: const Text('Unable to load chart · Retry'),
                      ),
                    ),
                data:
                    (lines) => WandbLineChart(
                      series: lines,
                      smoothing: rule.smoothing,
                      smoothingType: rule.smoothingType,
                      showOriginal: rule.showOriginal,
                      ignoreOutliers: rule.ignoreOutliers,
                      logScale: rule.logScale,
                      xAxis: rule.xAxis,
                      xAxisMin: rule.resolvedXMin,
                      xAxisMax: rule.resolvedXMax,
                      showLegend: false,
                      yAxisMin: rule.resolvedMin,
                      yAxisMax: rule.resolvedMax,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PanelDetailScreen extends ConsumerStatefulWidget {
  const PanelDetailScreen({
    super.key,
    required this.request,
    this.systemSeries,
  });
  final PanelRequest request;
  final MetricSeries? systemSeries;

  @override
  ConsumerState<PanelDetailScreen> createState() => _PanelDetailScreenState();
}

class _PanelDetailScreenState extends ConsumerState<PanelDetailScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
  }

  void _refresh() {
    final request = widget.request;
    if (widget.systemSeries == null) {
      if (ref.read(panelSeriesProvider(request)).isLoading) return;
      refreshPanelSeries(ref, request);
    } else {
      ref.invalidate(
        runSystemSeriesProvider(
          RunRef(
            entity: request.project.entity,
            project: request.project.project,
            runName: request.runName!,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final preferences = ref.watch(mobilePreferencesProvider);
    final starred = isMetricStarred(
      preferences,
      request.project,
      request.panel.id,
    );
    final scope =
        request.runName == null
            ? request.project.path
            : '${request.project.path}/${request.runName}';
    final workspace =
        ref.watch(workspaceSettingsProvider(request.project)).valueOrNull;
    final rule = preferences.ruleFor(scope, request.panel, workspace);
    final grouped =
        request.runName == null &&
        groupingKeys(
          preferences.grouping,
          workspace,
          request.project.path,
        ).isNotEmpty;
    final metricKeys =
        ref.watch(projectMetricKeysProvider(request.project)).valueOrNull ??
        const <String>[];
    final series =
        widget.systemSeries == null
            ? ref.watch(panelSeriesProvider(request))
            : ref
                .watch(
                  runSystemSeriesProvider(
                    RunRef(
                      entity: request.project.entity,
                      project: request.project.project,
                      runName: request.runName!,
                    ),
                  ),
                )
                .whenData(
                  (lines) =>
                      lines
                          .where((line) => line.key == request.panel.id)
                          .toList(),
                );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          request.panel.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: starred ? 'Unstar panel' : 'Star panel',
            onPressed:
                () => ref
                    .read(mobilePreferencesProvider.notifier)
                    .toggleMetric(request.project.path, request.panel.id),
            icon: WandbIcon(
              starred ? 'star_(filled)' : 'star',
              color: starred ? WandbColors.star : null,
            ),
          ),
          if (widget.systemSeries == null && request.panel.isAuto)
            IconButton(
              tooltip: 'Automation alerts',
              onPressed:
                  () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder:
                        (_) => MetricAlertSheet(
                          project: request.project,
                          metric: request.panel.id,
                        ),
                  ),
              icon: const WandbIcon('bell_notifications'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: series.when(
                      loading:
                          () =>
                              const Center(child: CircularProgressIndicator()),
                      error:
                          (error, _) => MobileEmptyState(
                            title: 'Unable to load chart',
                            message: '$error',
                            icon: 'warning',
                            onRetry: _refresh,
                          ),
                      data:
                          (lines) => WandbLineChart(
                            series: lines,
                            smoothing: rule.smoothing,
                            smoothingType: rule.smoothingType,
                            showOriginal: rule.showOriginal,
                            ignoreOutliers: rule.ignoreOutliers,
                            legendPosition: rule.legendPosition,
                            logScale: rule.logScale,
                            xAxis: rule.xAxis,
                            xAxisMin: rule.resolvedXMin,
                            xAxisMax: rule.resolvedXMax,
                            yAxisMin: rule.resolvedMin,
                            yAxisMax: rule.resolvedMax,
                          ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Flexible(
                    child: TextButton.icon(
                      onPressed:
                          () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder:
                                (_) => KeyPicker(
                                  title: 'X axis',
                                  options: [
                                    ...builtInXAxes,
                                    for (final key in metricKeys)
                                      if (!builtInXAxes.contains(key)) key,
                                  ],
                                  selected: rule.xAxis,
                                  labelOf: xAxisLabel,
                                  onSelected: (value) {
                                    // Read at tap time: the workspace may
                                    // have arrived since this screen built.
                                    final current = ref
                                        .read(mobilePreferencesProvider)
                                        .ruleFor(
                                          scope,
                                          request.panel,
                                          ref
                                              .read(
                                                workspaceSettingsProvider(
                                                  request.project,
                                                ),
                                              )
                                              .valueOrNull,
                                        );
                                    ref
                                        .read(
                                          mobilePreferencesProvider.notifier,
                                        )
                                        .setRule(
                                          request.panel.id,
                                          current.copyWith(xAxis: value),
                                        );
                                  },
                                ),
                          ),
                      icon: const WandbIcon('line_plot', size: 18),
                      label: Text(
                        'X: ${xAxisLabel(rule.xAxis)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh chart',
                    onPressed: _refresh,
                    icon: const WandbIcon('reload_(refresh)'),
                  ),
                  IconButton(
                    tooltip: 'Line plot settings',
                    icon: const WandbIcon('settings_parameters'),
                    onPressed:
                        () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder:
                              (_) => LinePlotSettings(
                                rule: rule,
                                scope: 'Applies to this line plot',
                                xAxisOptions: metricKeys,
                                resetRule: preferences.inheritedRuleFor(
                                  scope,
                                  request.panel,
                                  workspace,
                                ),
                                grouped: grouped,
                                onChanged:
                                    (value) => ref
                                        .read(
                                          mobilePreferencesProvider.notifier,
                                        )
                                        .setRule(request.panel.id, value),
                                onReset:
                                    () => ref
                                        .read(
                                          mobilePreferencesProvider.notifier,
                                        )
                                        .resetRule(request.panel.id),
                              ),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
