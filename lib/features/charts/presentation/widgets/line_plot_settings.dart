import 'package:flutter/material.dart';

import '../../../../core/widgets/wandb_icon.dart';
import '../../models/metric_chart_rule.dart';
import 'wandb_line_chart.dart';

class LinePlotSettings extends StatefulWidget {
  const LinePlotSettings({
    super.key,
    required this.rule,
    required this.scope,
    required this.onChanged,
    required this.onReset,
    required this.xAxisOptions,
    this.resetRule = MetricChartRule.defaults,
  });
  final MetricChartRule rule;
  final String scope;
  final ValueChanged<MetricChartRule> onChanged;
  final VoidCallback onReset;
  final MetricChartRule resetRule;

  /// History keys offered as custom X axes after the built-in ones.
  final List<String> xAxisOptions;

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
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('X axis'),
            subtitle: Text(
              xAxisLabel(_rule.xAxis),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const WandbIcon('chevron_(next)', size: 18),
            onTap:
                () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder:
                      (_) => XAxisPicker(
                        selected: _rule.xAxis,
                        options: widget.xAxisOptions,
                        onSelected: (value) {
                          setState(() => _rule = _rule.copyWith(xAxis: value));
                          widget.onChanged(_rule);
                        },
                      ),
                ),
          ),
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

/// Bottom sheet listing the built-in X axes followed by searchable history
/// keys, as in the web's panel X-axis menu.
class XAxisPicker extends StatefulWidget {
  const XAxisPicker({
    super.key,
    required this.selected,
    required this.options,
    required this.onSelected,
  });
  final String selected;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  State<XAxisPicker> createState() => _XAxisPickerState();
}

class _XAxisPickerState extends State<XAxisPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final matches = [
      for (final axis in builtInXAxes)
        if (xAxisLabel(axis).toLowerCase().contains(query)) axis,
      for (final key in widget.options)
        if (!builtInXAxes.contains(key) && key.toLowerCase().contains(query))
          key,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'X axis',
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search X axis',
                  prefixIcon: Padding(
                    padding: EdgeInsets.all(12),
                    child: WandbIcon('search'),
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final axis = matches[index];
                  return ListTile(
                    title: Text(
                      xAxisLabel(axis),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing:
                        axis == widget.selected
                            ? const WandbIcon('checkmark', size: 18)
                            : null,
                    onTap: () {
                      widget.onSelected(axis);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
