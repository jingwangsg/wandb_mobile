import 'package:flutter/material.dart';

import '../../../../core/models/metric_point.dart';
import '../../../../core/widgets/wandb_mark_icon.dart';
import '../../models/metric_chart_rule.dart';
import 'wandb_line_chart.dart';

class MetricChartCard extends StatelessWidget {
  const MetricChartCard({
    super.key,
    required this.series,
    required this.rule,
    required this.onRuleChanged,
    this.onExpand,
    this.xAxisMode = XAxisMode.step,
  });

  final MetricSeries series;
  final MetricChartRule rule;
  final ValueChanged<MetricChartRule> onRuleChanged;
  final VoidCallback? onExpand;
  final XAxisMode xAxisMode;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onExpand,
      child: Card(
        key: Key('metric-chart-card-${series.key}'),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const WandbMarkIcon(size: 18, compact: true),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          series.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _ruleSummary(rule),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onExpand != null)
                    IconButton(
                      key: Key('expand-chart-${series.key}'),
                      onPressed: onExpand,
                      icon: const Icon(
                        Icons.open_in_full,
                        size: 20,
                        color: Colors.white54,
                      ),
                      tooltip: 'Expand',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: WandbLineChart(
                      key: Key('metric-chart-${series.key}'),
                      series: [series],
                      smoothing: rule.smoothing,
                      xAxisMode: xAxisMode,
                      yAxisMin: rule.resolvedMin,
                      yAxisMax: rule.resolvedMax,
                      showLegend: false,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _ruleSummary(MetricChartRule rule) {
  final minText = rule.useAutoMin ? 'auto' : (rule.min?.toString() ?? 'manual');
  final maxText = rule.useAutoMax ? 'auto' : (rule.max?.toString() ?? 'manual');
  return 'Smooth ${rule.smoothing.toStringAsFixed(2)} • Y $minText → $maxText';
}
