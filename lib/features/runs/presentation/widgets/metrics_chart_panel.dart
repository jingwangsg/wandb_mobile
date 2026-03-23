import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/diagnostics/diagnostic_format.dart';
import '../../../../core/diagnostics/runtime_diagnostics.dart';
import '../../../../core/models/metric_point.dart';
import '../../../../core/models/run.dart';
import '../../../../core/widgets/wandb_mark_icon.dart';
import '../../../charts/models/metric_chart_rule.dart';
import '../../../charts/models/run_chart_preferences.dart';
import '../../../charts/presentation/widgets/grouped_chart_area.dart';
import '../../../charts/providers/chart_preferences_providers.dart';
import '../../providers/runs_providers.dart';
import 'grouped_metric_selector.dart';

const _defaultMetricSelectionLimit = 3;
const _defaultMetricPrefixes = ['train/', 'val/', 'valid/', 'eval/', 'test/'];
const _deprioritizedMetricPrefixes = ['system/', 'slowest_rank/', 'straggler/'];
const _headlineMetricTokens = [
  'loss',
  'accuracy',
  'acc',
  'error',
  'precision',
  'recall',
  'f1',
  'auc',
  'iou',
  'bleu',
  'perplexity',
  'reward',
];
const _supportingMetricTokens = ['grad_norm', 'norm'];
const _deprioritizedMetricTokens = [
  'epoch',
  'step',
  'learning_rate',
  'lr',
  'runtime',
  'time',
  'tokens',
  'batch',
  'pixel_elements',
  'memory',
  'cpu',
  'gpu',
  'rank',
];

/// Panel that loads and displays metric charts for a run.
class MetricsChartPanel extends ConsumerStatefulWidget {
  const MetricsChartPanel({
    super.key,
    required this.entity,
    required this.project,
    required this.runName,
    required this.run,
  });

  final String entity;
  final String project;
  final String runName;
  final WandbRun run;

  @override
  ConsumerState<MetricsChartPanel> createState() => _MetricsChartPanelState();
}

class _MetricsChartPanelState extends ConsumerState<MetricsChartPanel> {
  final Set<String> _selectedKeys = {};
  final Set<String> _expandedGroupPaths = {};
  final Set<String> _collapsedChartGroups = {};

  Map<String, MetricChartRule> _rulesByKey = const {};
  bool _loaded = false;
  bool _loading = false;
  bool _restoringPreferences = true;
  String? _error;
  int _requestSequence = 0;
  List<MetricSeries> _series = [];
  Map<String, Object?>? _lastRequestDetails;

  List<String> get _availableKeys {
    final keys = <String>{};

    final historyKeys = widget.run.historyKeys?['keys'];
    if (historyKeys is Map) {
      keys.addAll(historyKeys.keys.cast<String>());
    }

    if (keys.isEmpty) {
      keys.addAll(widget.run.summaryMetrics.keys);
    }

    return keys.where((key) => !key.startsWith('_')).toList()..sort();
  }

  List<String> get _defaultMetricKeys {
    final historyKeyMetadata = widget.run.historyKeys?['keys'];
    final historyKeyMap =
        historyKeyMetadata is Map
            ? historyKeyMetadata.cast<String, dynamic>()
            : const <String, dynamic>{};
    final rankedKeys = [..._availableKeys];
    rankedKeys.sort((a, b) {
      final scoreComparison = _metricPriorityScore(
        b,
        historyKeyMap,
      ).compareTo(_metricPriorityScore(a, historyKeyMap));
      if (scoreComparison != 0) return scoreComparison;
      return a.compareTo(b);
    });
    return rankedKeys.take(_defaultMetricSelectionLimit).toList();
  }

  @override
  void initState() {
    super.initState();
    _restorePreferencesAndLoad();
  }

  Future<void> _loadMetrics() async {
    final selectedKeys = _selectedKeys.toList();
    final requestId = ++_requestSequence;

    if (selectedKeys.isEmpty) {
      if (!mounted) return;
      setState(() {
        _series = const [];
        _loaded = false;
        _loading = false;
        _error = null;
      });
      return;
    }

    final requestDetails = <String, Object?>{
      'entity': widget.entity,
      'project': widget.project,
      'runName': widget.runName,
      'keys': [...selectedKeys]..sort(),
      'samples': 500,
    };

    setState(() {
      _loading = true;
      _error = null;
      _lastRequestDetails = requestDetails;
    });

    RuntimeDiagnostics.instance.record(
      'metrics_request',
      'Loading sampled history for Metrics tab',
      data: requestDetails,
    );

    try {
      final repo = ref.read(runsRepositoryProvider);
      final series = await repo.getSampledHistory(
        entity: widget.entity,
        project: widget.project,
        runName: widget.runName,
        keys: selectedKeys,
      );
      if (!mounted || requestId != _requestSequence) return;

      setState(() {
        _series = series;
        _loaded = true;
        _loading = false;
      });
      RuntimeDiagnostics.instance.record(
        'metrics_request_succeeded',
        'Loaded sampled history for Metrics tab',
        data: {
          ...requestDetails,
          'seriesCount': series.length,
          'pointCounts': {
            for (final metricSeries in series)
              metricSeries.key: metricSeries.points.length,
          },
        },
      );
    } catch (e, st) {
      RuntimeDiagnostics.instance.record(
        'metrics_request_failed',
        'Failed to load sampled history for Metrics tab',
        data: {...requestDetails, 'error': e.toString()},
        stackTrace: st,
      );
      if (!mounted || requestId != _requestSequence) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _restorePreferencesAndLoad() async {
    final availableKeys = _availableKeys;
    if (availableKeys.isEmpty) {
      if (!mounted) return;
      setState(() => _restoringPreferences = false);
      return;
    }

    final store = ref.read(runChartPreferencesStoreProvider);
    final preferences = await store.read(
      entity: widget.entity,
      project: widget.project,
      runName: widget.runName,
    );
    if (!mounted) return;

    final restoredKeys = preferences
        .selectedKeysFor(ChartPreferenceScope.metrics)
        .where(availableKeys.contains)
        .toList(growable: false);
    final nextSelected =
        restoredKeys.isNotEmpty ? restoredKeys : _defaultMetricKeys;
    final nextExpanded = <String>{};
    for (final key in nextSelected) {
      nextExpanded.addAll(metricGroupPathsForKey(key));
    }

    final nextRules = <String, MetricChartRule>{
      for (final entry
          in preferences.rulesFor(ChartPreferenceScope.metrics).entries)
        if (availableKeys.contains(entry.key)) entry.key: entry.value,
    };

    setState(() {
      _selectedKeys
        ..clear()
        ..addAll(nextSelected);
      _expandedGroupPaths
        ..clear()
        ..addAll(nextExpanded);
      _rulesByKey = Map.unmodifiable(nextRules);
      _restoringPreferences = false;
    });

    await _loadMetrics();
  }

  void _toggleMetricSelection(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
        _expandedGroupPaths.addAll(metricGroupPathsForKey(key));
      }
    });
    unawaited(_persistSelection());
    _loadMetrics();
  }

  void _setGroupExpanded(String path, bool expanded) {
    setState(() {
      if (expanded) {
        _expandedGroupPaths.add(path);
      } else {
        _expandedGroupPaths.remove(path);
      }
    });
  }

  Future<void> _showMetricSelectorSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Select Metrics',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${_selectedKeys.length} selected',
                            style: const TextStyle(color: Colors.white54),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: GroupedMetricSelector(
                        metricKeys: _availableKeys,
                        selectedKeys: _selectedKeys,
                        expandedGroupPaths: _expandedGroupPaths,
                        onToggleMetric: (key) {
                          _toggleMetricSelection(key);
                          sheetSetState(() {});
                        },
                        onToggleGroup: (path, expanded) {
                          _setGroupExpanded(path, expanded);
                          sheetSetState(() {});
                        },
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableKeys = _availableKeys;

    if (availableKeys.isEmpty) {
      return const Center(child: Text('No metrics logged'));
    }
    if (_restoringPreferences && !_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 500) {
          return Row(
            children: [
              SizedBox(
                width: 240,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Metrics',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                          Text(
                            '${_selectedKeys.length} selected',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GroupedMetricSelector(
                        metricKeys: availableKeys,
                        selectedKeys: _selectedKeys,
                        expandedGroupPaths: _expandedGroupPaths,
                        onToggleMetric: _toggleMetricSelection,
                        onToggleGroup: _setGroupExpanded,
                        compact: true,
                        padding: const EdgeInsets.only(bottom: 8),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: _buildChartArea()),
            ],
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _showMetricSelectorSheet,
                    icon: const WandbMarkIcon(size: 18, compact: true),
                    label: Text('Metrics (${_selectedKeys.length})'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectionSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildChartArea()),
          ],
        );
      },
    );
  }

  String get _selectionSummary {
    if (_selectedKeys.isEmpty) return 'No metrics selected';
    final selected = _selectedKeys.toList(growable: false);
    if (selected.length == 1) return selected.first;
    return '${selected.first}, +${selected.length - 1} more';
  }

  Widget _buildChartArea() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildErrorView();
    if (!_loaded || _series.isEmpty) {
      return const Center(child: Text('Select metrics to chart'));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 8),
      child: GroupedChartArea(
        series: _selectedSeries,
        rulesByKey: _rulesByKey,
        collapsedGroups: _collapsedChartGroups,
        onToggleGroup: (group) {
          setState(() {
            if (_collapsedChartGroups.contains(group)) {
              _collapsedChartGroups.remove(group);
            } else {
              _collapsedChartGroups.add(group);
            }
          });
        },
        onRuleChanged: _updateRule,
      ),
    );
  }

  List<MetricSeries> get _selectedSeries {
    final seriesByKey = {for (final series in _series) series.key: series};

    return _selectedKeys
        .map(
          (key) =>
              seriesByKey[key] ??
              MetricSeries(key: key, points: const <MetricPoint>[]),
        )
        .toList(growable: false);
  }

  void _updateRule(String key, MetricChartRule rule) {
    setState(() {
      _rulesByKey = Map.unmodifiable({..._rulesByKey, key: rule});
    });
    unawaited(
      ref
          .read(runChartPreferencesStoreProvider)
          .saveRule(
            entity: widget.entity,
            project: widget.project,
            runName: widget.runName,
            scope: ChartPreferenceScope.metrics,
            key: key,
            rule: rule,
          ),
    );
  }

  Future<void> _persistSelection() {
    return ref
        .read(runChartPreferencesStoreProvider)
        .saveSelectedKeys(
          entity: widget.entity,
          project: widget.project,
          runName: widget.runName,
          scope: ChartPreferenceScope.metrics,
          keys: _selectedKeys.toList(growable: false),
        );
  }

  Widget _buildErrorView() {
    final diagnostics = RuntimeDiagnostics.instance;
    final requestText =
        _lastRequestDetails == null
            ? 'No request captured.'
            : formatDiagnosticJson(_lastRequestDetails!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Failed to load metrics',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SelectableText(
          _error ?? 'Unknown error',
          style: const TextStyle(
            color: Colors.white70,
            fontFamily: 'JetBrains Mono',
          ),
        ),
        const SizedBox(height: 16),
        _DiagnosticSection(title: 'Request Parameters', body: requestText),
        const SizedBox(height: 12),
        _DiagnosticSection(
          title: 'Recent Diagnostics',
          body: diagnostics.formatRecentEntries(),
        ),
        if (diagnostics.logFilePath != null) ...[
          const SizedBox(height: 12),
          _DiagnosticSection(
            title: 'Local Log File',
            body: diagnostics.logFilePath!,
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _loadMetrics,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _DiagnosticSection extends StatelessWidget {
  const _DiagnosticSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            body,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

int _metricPriorityScore(String key, Map<String, dynamic> historyKeyMap) {
  final lowerKey = key.toLowerCase();
  var score = 0;

  if (_defaultMetricPrefixes.any(lowerKey.startsWith)) {
    score += 500;
  }

  if (_deprioritizedMetricPrefixes.any(lowerKey.startsWith)) {
    score -= 350;
  }

  if (_headlineMetricTokens.any(lowerKey.contains)) {
    score += 350;
  } else if (_supportingMetricTokens.any(lowerKey.contains)) {
    score += 180;
  }

  if (_deprioritizedMetricTokens.any(lowerKey.contains)) {
    score -= 275;
  }

  score += _historyPointCountForKey(key, historyKeyMap) ~/ 200;
  return score;
}

int _historyPointCountForKey(String key, Map<String, dynamic> historyKeyMap) {
  final entry = historyKeyMap[key];
  if (entry is! Map) return 0;

  final typeCounts = entry['typeCounts'];
  if (typeCounts is! List) return 0;

  var count = 0;
  for (final typeCount in typeCounts) {
    if (typeCount is! Map) continue;
    if (typeCount['type'] != 'number') continue;
    final rawCount = typeCount['count'];
    if (rawCount is num) {
      count += rawCount.toInt();
    }
  }
  return count;
}
