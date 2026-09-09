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
import '../providers/panel_providers.dart';
import '../models/metric_chart_rule.dart';
import 'widgets/line_plot_settings.dart';
import 'widgets/image_metric_panel.dart';
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
            metric: metric,
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

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(mobilePreferencesProvider);
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
              IconButton(
                tooltip: 'Line plot settings',
                icon: const WandbIcon('settings_parameters'),
                onPressed:
                    () => showModalBottomSheet<void>(
                      context: context,
                      useSafeArea: true,
                      builder:
                          (_) => LinePlotSettings(
                            rule:
                                preferences.defaultRules[scope] ??
                                preferences.ruleFor(scope, ''),
                            scope:
                                widget.run == null
                                    ? 'Applies to all line plots in this project'
                                    : 'Applies to all line plots in this run',
                            onChanged:
                                (rule) => ref
                                    .read(mobilePreferencesProvider.notifier)
                                    .setDefaults(scope, rule),
                            onReset:
                                () => ref
                                    .read(mobilePreferencesProvider.notifier)
                                    .setDefaults(
                                      scope,
                                      const MetricChartRule(),
                                    ),
                          ),
                    ),
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
              final groups = <String, List<String>>{};
              for (final name in rankedNames) {
                if (_starredOnly &&
                    !isMetricStarred(preferences, widget.project, name)) {
                  continue;
                }
                if (_pattern != null && !_pattern!.hasMatch(name)) continue;
                final slash = name.indexOf('/');
                final section =
                    slash > 0 ? name.substring(0, slash) : 'Metrics';
                (groups[section] ??= []).add(name);
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
                            itemBuilder:
                                (context, index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child:
                                      widget.run != null &&
                                              imageMetrics.contains(
                                                groups[section]![index],
                                              )
                                          ? ImageMetricPanel(
                                            run: RunRef(
                                              entity: widget.project.entity,
                                              project: widget.project.project,
                                              runName: widget.run!.name,
                                            ),
                                            metric: groups[section]![index],
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
                                            metric: groups[section]![index],
                                          ),
                                ),
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
                                    metric: systemLines[index].key,
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
    required this.metric,
    this.runName,
    this.systemSeries,
  });
  final ProjectRef project;
  final String metric;
  final String? runName;
  final MetricSeries? systemSeries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(mobilePreferencesProvider);
    final starred = isMetricStarred(preferences, project, metric);
    final scope = runName == null ? project.path : '${project.path}/$runName';
    final rule = preferences.ruleFor(scope, metric);
    final request = (project: project, runName: runName, metric: metric);
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
                        metric,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: starred ? 'Unstar panel' : 'Star panel',
                  onPressed:
                      () => ref
                          .read(mobilePreferencesProvider.notifier)
                          .toggleMetric(project.path, metric),
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
                        onPressed:
                            () => ref.invalidate(panelSeriesProvider(request)),
                        child: const Text('Unable to load chart · Retry'),
                      ),
                    ),
                data:
                    (lines) => WandbLineChart(
                      series: lines,
                      smoothing: rule.smoothing,
                      logScale: rule.logScale,
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
  XAxisMode _axis = XAxisMode.step;
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
      ref.invalidate(panelSeriesProvider(request));
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
      request.metric,
    );
    final scope =
        request.runName == null
            ? request.project.path
            : '${request.project.path}/${request.runName}';
    final rule = preferences.ruleFor(scope, request.metric);
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
                          .where((line) => line.key == request.metric)
                          .toList(),
                );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          request.metric,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: starred ? 'Unstar panel' : 'Star panel',
            onPressed:
                () => ref
                    .read(mobilePreferencesProvider.notifier)
                    .toggleMetric(request.project.path, request.metric),
            icon: WandbIcon(
              starred ? 'star_(filled)' : 'star',
              color: starred ? WandbColors.star : null,
            ),
          ),
          if (widget.systemSeries == null)
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
                          metric: request.metric,
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
                            onRetry:
                                () => ref.invalidate(
                                  panelSeriesProvider(request),
                                ),
                          ),
                      data:
                          (lines) => WandbLineChart(
                            series: lines,
                            smoothing: rule.smoothing,
                            logScale: rule.logScale,
                            xAxisMode: _axis,
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
                  DropdownButton<XAxisMode>(
                    value: _axis,
                    items:
                        XAxisMode.values
                            .map(
                              (mode) => DropdownMenuItem(
                                value: mode,
                                child: Text(mode.label),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _axis = value);
                    },
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
                          useSafeArea: true,
                          builder:
                              (_) => LinePlotSettings(
                                rule: rule,
                                scope: 'Applies to this line plot',
                                resetRule:
                                    preferences.defaultRules[scope] ??
                                    MetricChartRule.defaults,
                                onChanged:
                                    (value) => ref
                                        .read(
                                          mobilePreferencesProvider.notifier,
                                        )
                                        .setRule(request.metric, value),
                                onReset:
                                    () => ref
                                        .read(
                                          mobilePreferencesProvider.notifier,
                                        )
                                        .resetRule(request.metric),
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
