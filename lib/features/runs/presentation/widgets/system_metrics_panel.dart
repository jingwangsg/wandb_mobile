import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/diagnostics/diagnostic_format.dart';
import '../../../../core/diagnostics/runtime_diagnostics.dart';
import '../../../../core/models/metric_point.dart';
import '../../../../core/widgets/wandb_mark_icon.dart';
import '../../../charts/models/metric_chart_rule.dart';
import '../../../charts/models/run_chart_preferences.dart';
import '../../../charts/presentation/widgets/grouped_chart_area.dart';
import '../../../charts/presentation/widgets/wandb_line_chart.dart';
import '../../../charts/providers/chart_preferences_providers.dart';
import '../../providers/runs_providers.dart';
import 'grouped_metric_selector.dart';

const _defaultSystemSelectionLimit = 3;
const _systemPreferredTokens = [
  'gpu',
  'cpu',
  'memory',
  'util',
  'temperature',
  'temp',
  'power',
  'disk',
  'network',
];
const _systemDeprioritizedTokens = [
  'error',
  'errors',
  'pid',
  'process',
  'correctedmemoryerrors',
  'uncorrectedmemoryerrors',
];

class SystemMetricsPanel extends ConsumerStatefulWidget {
  const SystemMetricsPanel({
    super.key,
    required this.entity,
    required this.project,
    required this.runName,
  });

  final String entity;
  final String project;
  final String runName;

  @override
  ConsumerState<SystemMetricsPanel> createState() => _SystemMetricsPanelState();
}

class _SystemMetricsPanelState extends ConsumerState<SystemMetricsPanel> {
  final Set<String> _selectedKeys = {};
  final Set<String> _expandedGroupPaths = {};
  final Set<String> _collapsedChartGroups = {};
  bool _selectorVisible = true;

  Map<String, MetricChartRule> _rulesByKey = const {};
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  int _requestSequence = 0;
  List<String> _availableKeys = const [];
  List<_SystemMetricRow> _rows = const [];
  List<MetricSeries> _series = const [];
  XAxisMode _xAxisMode = XAxisMode.step;
  Map<String, Object?>? _lastRequestDetails;

  @override
  void initState() {
    super.initState();
    _loadSystemMetrics();
  }

  Future<void> _loadSystemMetrics() async {
    final requestId = ++_requestSequence;
    final requestDetails = <String, Object?>{
      'entity': widget.entity,
      'project': widget.project,
      'runName': widget.runName,
      'samples': 500,
    };

    setState(() {
      _loading = true;
      _error = null;
      _lastRequestDetails = requestDetails;
    });

    RuntimeDiagnostics.instance.record(
      'system_metrics_request',
      'Loading system metrics for Run detail',
      data: requestDetails,
    );

    try {
      final repo = ref.read(runsRepositoryProvider);
      final rawRows = await repo.getSystemMetrics(
        entity: widget.entity,
        project: widget.project,
        runName: widget.runName,
      );
      final dataset = _SystemMetricsDataset.fromRows(rawRows);
      if (!mounted || requestId != _requestSequence) return;

      final preferences = await ref
          .read(runChartPreferencesStoreProvider)
          .read(
            entity: widget.entity,
            project: widget.project,
            runName: widget.runName,
          );
      if (!mounted || requestId != _requestSequence) return;

      final restoredSelection = preferences
          .selectedKeysFor(ChartPreferenceScope.system)
          .where(dataset.availableKeys.contains)
          .toList(growable: false);
      final nextSelected = <String>{
        ..._selectedKeys.where(dataset.availableKeys.contains),
        ...restoredSelection,
      };
      if (nextSelected.isEmpty) {
        nextSelected.addAll(_defaultSystemKeys(dataset.availableKeys));
      }

      final nextExpanded = <String>{..._expandedGroupPaths};
      for (final key in nextSelected) {
        nextExpanded.addAll(metricGroupPathsForKey(key));
      }

      final nextSeries = _buildSeries(dataset.rows, nextSelected);
      final nextRules = <String, MetricChartRule>{
        for (final entry
            in preferences.rulesFor(ChartPreferenceScope.system).entries)
          if (dataset.availableKeys.contains(entry.key)) entry.key: entry.value,
      };

      setState(() {
        _availableKeys = dataset.availableKeys;
        _rows = dataset.rows;
        _series = nextSeries;
        _rulesByKey = Map.unmodifiable(nextRules);
        _xAxisMode =
            dataset.hasTimestamps ? XAxisMode.relativeTime : XAxisMode.step;
        _selectedKeys
          ..clear()
          ..addAll(nextSelected);
        _expandedGroupPaths
          ..clear()
          ..addAll(nextExpanded);
        _loaded = true;
        _loading = false;
      });

      RuntimeDiagnostics.instance.record(
        'system_metrics_request_succeeded',
        'Loaded system metrics for Run detail',
        data: {
          ...requestDetails,
          'rowCount': rawRows.length,
          'availableKeyCount': dataset.availableKeys.length,
          'pointCounts': {
            for (final metricSeries in nextSeries)
              metricSeries.key: metricSeries.points.length,
          },
        },
      );
    } catch (e, st) {
      RuntimeDiagnostics.instance.record(
        'system_metrics_request_failed',
        'Failed to load system metrics for Run detail',
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

  void _toggleMetricSelection(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
        _expandedGroupPaths.addAll(metricGroupPathsForKey(key));
      }
      _series = _buildSeries(_rows, _selectedKeys);
    });
    unawaited(_persistSelection());
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
                              'Select System Metrics',
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
    if (_loading && !_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _buildErrorView();
    if (_loaded && _availableKeys.isEmpty) {
      return const Center(child: Text('No system metrics logged'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 500) {
          return Column(
            children: [
              if (!_selectorVisible)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () =>
                            setState(() => _selectorVisible = true),
                        icon: const Icon(Icons.menu, size: 20),
                        tooltip: 'Show selector',
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'System (${_selectedKeys.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
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
              Expanded(
                child: Row(
                  children: [
                    if (_selectorVisible) ...[
                      SizedBox(
                        width: 240,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 8, 8),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'System Metrics',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${_selectedKeys.length}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white38,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(
                                        () => _selectorVisible = false),
                                    icon: const Icon(
                                        Icons.chevron_left, size: 20),
                                    tooltip: 'Hide selector',
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: GroupedMetricSelector(
                                metricKeys: _availableKeys,
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
                    ],
                    Expanded(child: _buildChartArea()),
                  ],
                ),
              ),
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
                    label: Text('System (${_selectedKeys.length})'),
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
    if (_selectedKeys.isEmpty) {
      return const Center(child: Text('Select system metrics to chart'));
    }
    if (_series.isEmpty) {
      return const Center(child: Text('No system metrics found for selection'));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 8),
      child: GroupedChartArea(
        series: _series,
        rulesByKey: _rulesByKey,
        xAxisMode: _xAxisMode,
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
            scope: ChartPreferenceScope.system,
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
          scope: ChartPreferenceScope.system,
          keys: _selectedKeys.toList(growable: false),
        );
  }

  List<String> _defaultSystemKeys(List<String> availableKeys) {
    final rankedKeys = [...availableKeys];
    rankedKeys.sort((a, b) {
      final scoreComparison = _systemMetricPriorityScore(
        b,
      ).compareTo(_systemMetricPriorityScore(a));
      if (scoreComparison != 0) return scoreComparison;
      return a.compareTo(b);
    });
    return rankedKeys.take(_defaultSystemSelectionLimit).toList();
  }

  List<MetricSeries> _buildSeries(
    List<_SystemMetricRow> rows,
    Set<String> selectedKeys,
  ) {
    return selectedKeys.map((key) {
      final points = <MetricPoint>[];
      for (final row in rows) {
        final value = row.metrics[key];
        if (value == null) continue;
        points.add(
          MetricPoint(step: row.step, value: value, timestamp: row.timestamp),
        );
      }
      return MetricSeries(key: key, points: points);
    }).toList();
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
          'Failed to load system metrics',
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
        _SystemDiagnosticSection(
          title: 'Request Parameters',
          body: requestText,
        ),
        const SizedBox(height: 12),
        _SystemDiagnosticSection(
          title: 'Recent Diagnostics',
          body: diagnostics.formatRecentEntries(),
        ),
        if (diagnostics.logFilePath != null) ...[
          const SizedBox(height: 12),
          _SystemDiagnosticSection(
            title: 'Local Log File',
            body: diagnostics.logFilePath!,
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _loadSystemMetrics,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _SystemDiagnosticSection extends StatelessWidget {
  const _SystemDiagnosticSection({required this.title, required this.body});

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

class _SystemMetricsDataset {
  const _SystemMetricsDataset({
    required this.rows,
    required this.availableKeys,
    required this.hasTimestamps,
  });

  final List<_SystemMetricRow> rows;
  final List<String> availableKeys;
  final bool hasTimestamps;

  factory _SystemMetricsDataset.fromRows(List<Map<String, dynamic>> rawRows) {
    DateTime? firstTimestamp;
    for (final row in rawRows) {
      final timestamp = _extractTimestamp(row);
      if (timestamp != null) {
        firstTimestamp = timestamp;
        break;
      }
    }

    final parsedRows = <_SystemMetricRow>[];
    final availableKeys = <String>{};

    for (var index = 0; index < rawRows.length; index++) {
      final row = rawRows[index];
      final timestamp = _extractTimestamp(row);
      final step = _extractStep(row, index);
      final metrics = <String, double>{};
      _flattenNumericMetrics(row, metrics);
      availableKeys.addAll(metrics.keys);

      final plottedStep =
          timestamp != null && firstTimestamp != null
              ? timestamp.difference(firstTimestamp).inMilliseconds / 1000
              : step;

      parsedRows.add(
        _SystemMetricRow(
          step: plottedStep,
          timestamp: timestamp,
          metrics: Map.unmodifiable(metrics),
        ),
      );
    }

    final sortedKeys = availableKeys.toList()..sort();
    return _SystemMetricsDataset(
      rows: List.unmodifiable(parsedRows),
      availableKeys: List.unmodifiable(sortedKeys),
      hasTimestamps: firstTimestamp != null,
    );
  }
}

class _SystemMetricRow {
  const _SystemMetricRow({
    required this.step,
    required this.timestamp,
    required this.metrics,
  });

  final num step;
  final DateTime? timestamp;
  final Map<String, double> metrics;
}

void _flattenNumericMetrics(
  Map<String, dynamic> row,
  Map<String, double> output, [
  String prefix = '',
]) {
  row.forEach((key, value) {
    if (key.startsWith('_')) return;
    final nextKey = prefix.isEmpty ? key : '$prefix/$key';

    if (value is Map<String, dynamic>) {
      _flattenNumericMetrics(value, output, nextKey);
      return;
    }

    if (value is Map) {
      final nested = value.map(
        (nestedKey, nestedValue) => MapEntry(nestedKey.toString(), nestedValue),
      );
      _flattenNumericMetrics(nested, output, nextKey);
      return;
    }

    if (value is num) {
      final doubleValue = value.toDouble();
      if (doubleValue.isNaN || doubleValue.isInfinite) return;
      output[nextKey] = doubleValue;
    }
  });
}

DateTime? _extractTimestamp(Map<String, dynamic> row) {
  final rawValue = row['_timestamp'] ?? row['timestamp'];
  if (rawValue is num) {
    final milliseconds =
        rawValue > 1000000000000 ? rawValue.toInt() : rawValue.toInt() * 1000;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  if (rawValue is String) {
    final parsed = DateTime.tryParse(rawValue);
    if (parsed != null) return parsed;

    final parsedNumber = num.tryParse(rawValue);
    if (parsedNumber != null) {
      final milliseconds =
          parsedNumber > 1000000000000
              ? parsedNumber.toInt()
              : parsedNumber.toInt() * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
  }

  return null;
}

num _extractStep(Map<String, dynamic> row, int index) {
  final rawValue = row['_step'] ?? row['step'] ?? index;
  return rawValue is num ? rawValue : index;
}

int _systemMetricPriorityScore(String key) {
  final lowerKey = key.toLowerCase();
  var score = 0;

  for (var index = 0; index < _systemPreferredTokens.length; index++) {
    if (lowerKey.contains(_systemPreferredTokens[index])) {
      score += math.max(8, 32 - index * 3);
    }
  }

  if (lowerKey.contains('system/')) {
    score += 10;
  }

  if (lowerKey.contains('util') || lowerKey.contains('usage')) {
    score += 16;
  }

  if (lowerKey.contains('temp') || lowerKey.contains('temperature')) {
    score += 14;
  }

  if (_systemDeprioritizedTokens.any(lowerKey.contains)) {
    score -= 40;
  }

  return score;
}
