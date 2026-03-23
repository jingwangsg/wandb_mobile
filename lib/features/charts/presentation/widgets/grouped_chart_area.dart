import 'package:flutter/material.dart';

import '../../../../core/models/metric_point.dart';
import '../../../../core/utils/metric_grouping.dart';
import '../../models/metric_chart_rule.dart';
import 'expanded_chart_screen.dart';
import 'metric_chart_card.dart';
import 'wandb_line_chart.dart';

/// Displays metric charts grouped by prefix in collapsible sections.
class GroupedChartArea extends StatelessWidget {
  const GroupedChartArea({
    super.key,
    required this.series,
    required this.rulesByKey,
    required this.collapsedGroups,
    required this.onToggleGroup,
    required this.onRuleChanged,
    this.xAxisMode = XAxisMode.step,
  });

  final List<MetricSeries> series;
  final Map<String, MetricChartRule> rulesByKey;
  final Set<String> collapsedGroups;
  final ValueChanged<String> onToggleGroup;
  final void Function(String key, MetricChartRule rule) onRuleChanged;
  final XAxisMode xAxisMode;

  @override
  Widget build(BuildContext context) {
    final groups = groupSeriesByPrefix(series);

    // If only one group, skip the section header.
    if (groups.length == 1) {
      return _buildGrid(context, groups.first.series);
    }

    return CustomScrollView(
      slivers: [
        for (final group in groups) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              label: group.label.isEmpty ? 'Other' : '${group.label}/',
              count: group.series.length,
              collapsed: collapsedGroups.contains(group.label),
              onTap: () => onToggleGroup(group.label),
            ),
          ),
          if (!collapsedGroups.contains(group.label))
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 520,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 320,
                    ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildCard(context, group.series[index]),
                  childCount: group.series.length,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildGrid(BuildContext context, List<MetricSeries> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 520,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 320,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildCard(context, items[index]),
    );
  }

  Widget _buildCard(BuildContext context, MetricSeries s) {
    final rule = rulesByKey[s.key] ?? MetricChartRule.defaults;
    return MetricChartCard(
      series: s,
      rule: rule,
      xAxisMode: xAxisMode,
      onRuleChanged: (r) => onRuleChanged(s.key, r),
      onExpand: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => ExpandedChartScreen(
              series: s,
              rule: rule,
              xAxisMode: xAxisMode,
              onRuleChanged: (r) => onRuleChanged(s.key, r),
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 20,
              color: Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}
