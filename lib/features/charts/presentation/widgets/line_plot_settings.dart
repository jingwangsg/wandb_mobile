import 'package:flutter/material.dart';

import '../../../../core/widgets/wandb_icon.dart';
import '../../models/metric_chart_rule.dart';

class LinePlotSettings extends StatefulWidget {
  const LinePlotSettings({
    super.key,
    required this.rule,
    required this.scope,
    required this.onChanged,
    required this.onReset,
    this.resetRule = MetricChartRule.defaults,
  });
  final MetricChartRule rule;
  final String scope;
  final ValueChanged<MetricChartRule> onChanged;
  final VoidCallback onReset;
  final MetricChartRule resetRule;

  @override
  State<LinePlotSettings> createState() => _LinePlotSettingsState();
}

class _LinePlotSettingsState extends State<LinePlotSettings> {
  late MetricChartRule _rule = widget.rule;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Line plot settings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const WandbIcon('close'),
              ),
            ],
          ),
          Text(widget.scope, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Log scale (Y)'),
            value: _rule.logScale,
            onChanged: (value) {
              setState(() => _rule = _rule.copyWith(logScale: value));
              widget.onChanged(_rule);
            },
          ),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text('Smoothing')),
              SizedBox(
                width: 48,
                child: Text(
                  _rule.smoothing == 0
                      ? 'Off'
                      : _rule.smoothing.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          Text(
            'Time weighted EMA',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Slider(
            min: 0,
            max: 0.99,
            divisions: 99,
            value: _rule.smoothing.clamp(0, 0.99),
            label: _rule.smoothing.toStringAsFixed(2),
            onChanged: (value) {
              setState(() => _rule = _rule.copyWith(smoothing: value));
              widget.onChanged(_rule);
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() => _rule = widget.resetRule);
              widget.onReset();
            },
            child: Text(
              widget.scope == 'Applies to this line plot'
                  ? 'Reset this line plot'
                  : 'Reset to defaults',
            ),
          ),
        ],
      ),
    ),
  );
}
