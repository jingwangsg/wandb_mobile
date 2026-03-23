import 'package:flutter/material.dart';

import '../../../../core/models/metric_point.dart';
import '../../models/metric_chart_rule.dart';
import 'metric_chart_rule_editor.dart';
import 'wandb_line_chart.dart';

class ExpandedChartScreen extends StatefulWidget {
  const ExpandedChartScreen({
    super.key,
    required this.series,
    required this.rule,
    required this.onRuleChanged,
    this.xAxisMode = XAxisMode.step,
  });

  final MetricSeries series;
  final MetricChartRule rule;
  final ValueChanged<MetricChartRule> onRuleChanged;
  final XAxisMode xAxisMode;

  @override
  State<ExpandedChartScreen> createState() => _ExpandedChartScreenState();
}

class _ExpandedChartScreenState extends State<ExpandedChartScreen> {
  late MetricChartRule _rule;

  @override
  void initState() {
    super.initState();
    _rule = widget.rule;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.series.key,
          style: const TextStyle(
            fontSize: 16,
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: WandbLineChart(
                series: [widget.series],
                smoothing: _rule.smoothing,
                xAxisMode: widget.xAxisMode,
                yAxisMin: _rule.resolvedMin,
                yAxisMax: _rule.resolvedMax,
                xAxisMin: _rule.resolvedXMin,
                xAxisMax: _rule.resolvedXMax,
                showLegend: false,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: MetricChartRuleEditor(
                metricKey: widget.series.key,
                initialRule: _rule,
                onApply: (rule) {
                  setState(() => _rule = rule);
                  widget.onRuleChanged(rule);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
