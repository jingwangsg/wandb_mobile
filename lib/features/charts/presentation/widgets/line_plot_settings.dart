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
  late final _xMin = TextEditingController(text: _text(_rule.resolvedXMin));
  late final _xMax = TextEditingController(text: _text(_rule.resolvedXMax));
  late final _yMin = TextEditingController(text: _text(_rule.resolvedMin));
  late final _yMax = TextEditingController(text: _text(_rule.resolvedMax));

  static String _text(double? value) =>
      value?.toString().replaceFirst(RegExp(r'\.0$'), '') ?? '';

  @override
  void dispose() {
    for (final controller in [_xMin, _xMax, _yMin, _yMax]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _update(MetricChartRule rule) {
    setState(() => _rule = rule);
    widget.onChanged(_rule);
  }

  /// One axis bound. An empty or unfinished entry means auto.
  Widget _bound(
    TextEditingController controller,
    String label,
    MetricChartRule Function(double? value) apply,
  ) => Expanded(
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(labelText: label, hintText: 'Auto'),
      onChanged: (text) {
        final value = double.tryParse(text.trim());
        // Infinity and NaN parse but cannot be saved as JSON; treat as auto.
        _update(apply(value != null && value.isFinite ? value : null));
      },
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
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
                        onSelected:
                            (value) => _update(_rule.copyWith(xAxis: value)),
                      ),
                ),
          ),
          Row(
            children: [
              _bound(
                _xMin,
                'X min',
                (value) =>
                    _rule.copyWith(useAutoXMin: value == null, xMin: value),
              ),
              const SizedBox(width: 12),
              _bound(
                _xMax,
                'X max',
                (value) =>
                    _rule.copyWith(useAutoXMax: value == null, xMax: value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _bound(
                _yMin,
                'Y min',
                (value) =>
                    _rule.copyWith(useAutoMin: value == null, min: value),
              ),
              const SizedBox(width: 12),
              _bound(
                _yMax,
                'Y max',
                (value) =>
                    _rule.copyWith(useAutoMax: value == null, max: value),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Log scale (Y)'),
            value: _rule.logScale,
            onChanged: (value) => _update(_rule.copyWith(logScale: value)),
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
            onChanged: (value) => _update(_rule.copyWith(smoothing: value)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() {
                _rule = widget.resetRule;
                _xMin.text = _text(_rule.resolvedXMin);
                _xMax.text = _text(_rule.resolvedXMax);
                _yMin.text = _text(_rule.resolvedMin);
                _yMax.text = _text(_rule.resolvedMax);
              });
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
