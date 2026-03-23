import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/metric_point.dart';
import '../../../../core/models/run.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/diagnostics/diagnostic_format.dart';
import '../../../../core/diagnostics/runtime_diagnostics.dart';
import '../../../charts/presentation/widgets/wandb_line_chart.dart';
import '../../providers/runs_providers.dart';

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
  double _smoothing = 0.0;
  bool _loaded = false;
  List<MetricSeries> _series = [];
  bool _loading = false;
  String? _error;
  Map<String, Object?>? _lastRequestDetails;

  List<String> get _availableKeys {
    // Extract metric keys from historyKeys or summaryMetrics
    final keys = <String>{};

    // From historyKeys (if available)
    final hk = widget.run.historyKeys;
    if (hk != null) {
      // historyKeys format: {"keys": {"loss": {...}, "accuracy": {...}}}
      final keysMap = hk['keys'];
      if (keysMap is Map) {
        keys.addAll(keysMap.keys.cast<String>());
      }
    }

    // Fallback to summaryMetrics keys
    if (keys.isEmpty) {
      keys.addAll(widget.run.summaryMetrics.keys);
    }

    // Filter out internal keys
    return keys.where((k) => !k.startsWith('_')).toList()..sort();
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
    // Auto-select first few metrics
    final defaultKeys = _defaultMetricKeys;
    if (defaultKeys.isNotEmpty) {
      _selectedKeys.addAll(defaultKeys);
      _loadMetrics();
    }
  }

  Future<void> _loadMetrics() async {
    if (_selectedKeys.isEmpty) return;
    final requestDetails = <String, Object?>{
      'entity': widget.entity,
      'project': widget.project,
      'runName': widget.runName,
      'keys': _selectedKeys.toList()..sort(),
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
        keys: _selectedKeys.toList(),
      );
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
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableKeys = _availableKeys;

    if (availableKeys.isEmpty) {
      return const Center(child: Text('No metrics logged'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide: vertical sidebar for metric selector
        if (constraints.maxWidth >= 500) {
          return Row(
            children: [
              // Left sidebar: metric selector
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Text(
                        'Metrics',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: availableKeys.length,
                        itemBuilder:
                            (_, i) =>
                                _buildChip(availableKeys[i], compact: true),
                      ),
                    ),
                    _buildSmoothingControl(compact: true),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              // Right: chart
              Expanded(child: _buildChartArea()),
            ],
          );
        }

        // Narrow: horizontal chip bar on top
        return Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: availableKeys.length,
                itemBuilder:
                    (_, i) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildChip(availableKeys[i]),
                    ),
              ),
            ),
            Expanded(child: _buildChartArea()),
            if (_loaded && _series.isNotEmpty) _buildSmoothingControl(),
          ],
        );
      },
    );
  }

  Widget _buildChip(String key, {bool compact = false}) {
    final isSelected = _selectedKeys.contains(key);
    final colorIndex = _selectedKeys.toList().indexOf(key);
    final color =
        colorIndex >= 0
            ? WandbColors.chartPalette[colorIndex %
                WandbColors.chartPalette.length]
            : null;

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 2 : 0),
      child: FilterChip(
        label: Text(
          key,
          style: TextStyle(fontSize: compact ? 11 : 12),
          overflow: TextOverflow.ellipsis,
        ),
        selected: isSelected,
        selectedColor: color?.withValues(alpha: 0.3),
        checkmarkColor: color,
        visualDensity: compact ? VisualDensity.compact : null,
        onSelected: (selected) {
          setState(() {
            if (selected) {
              _selectedKeys.add(key);
            } else {
              _selectedKeys.remove(key);
            }
          });
          _loadMetrics();
        },
      ),
    );
  }

  Widget _buildChartArea() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildErrorView();
    if (!_loaded || _series.isEmpty) {
      return const Center(child: Text('Select metrics to chart'));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
      child: WandbLineChart(series: _series, smoothing: _smoothing),
    );
  }

  Widget _buildSmoothingControl({bool compact = false}) {
    if (!_loaded || _series.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 16, 0, compact ? 8 : 16, 8),
      child: Row(
        children: [
          Text(
            'Smooth',
            style: TextStyle(
              fontSize: compact ? 10 : 12,
              color: Colors.white54,
            ),
          ),
          Expanded(
            child: Slider(
              value: _smoothing,
              min: 0,
              max: 0.99,
              divisions: 99,
              label: _smoothing.toStringAsFixed(2),
              onChanged: (v) => setState(() => _smoothing = v),
            ),
          ),
          if (!compact)
            SizedBox(
              width: 40,
              child: Text(
                _smoothing.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
        ],
      ),
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
