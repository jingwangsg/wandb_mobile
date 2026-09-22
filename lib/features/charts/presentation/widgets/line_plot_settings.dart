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

  /// Gaussian and running average take a size in points; the exponential
  /// types take a weight below one.
  static bool _pointBased(String type) =>
      type == 'gaussian' || type == 'average';

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
  Widget build(BuildContext context) {
    final pointBased = _pointBased(_rule.smoothingType);
    final sliderMin = pointBased ? 1.0 : 0.0;
    final sliderMax = pointBased ? 100.0 : 0.99;
    final smoothingText =
        !_rule.smooths
            ? 'Off'
            : pointBased
            ? '${_rule.smoothing.round()} points'
            : _rule.smoothing.toStringAsFixed(2);
    return SafeArea(
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
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Exclude outliers when scaling'),
              value: _rule.ignoreOutliers,
              onChanged:
                  (value) => _update(_rule.copyWith(ignoreOutliers: value)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Point aggregation'),
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'sampling', label: Text('Sampling')),
                  ButtonSegment(
                    value: 'bucketing',
                    label: Text('Full fidelity'),
                  ),
                ],
                selected: {_rule.pointAggregation},
                onSelectionChanged:
                    (value) =>
                        _update(_rule.copyWith(pointAggregation: value.first)),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Legend position'),
              trailing: DropdownButton<String>(
                value: _rule.legendPosition,
                items: [
                  for (final position in legendPositions)
                    DropdownMenuItem(
                      value: position,
                      child: Text(
                        '${position[0].toUpperCase()}${position.substring(1)}',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _update(_rule.copyWith(legendPosition: value));
                  }
                },
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Smoothing')),
                DropdownButton<String>(
                  value: _rule.smoothingType,
                  items: [
                    for (final type in smoothingTypes)
                      DropdownMenuItem(
                        value: type,
                        child: Text(smoothingTypeLabel(type)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    // The parameter changes meaning with the type, so a
                    // switch across scales starts from that scale's default.
                    final rescale = _pointBased(value) != pointBased;
                    _update(
                      _rule.copyWith(
                        smoothingType: value,
                        smoothing:
                            rescale ? (_pointBased(value) ? 10 : 0.5) : null,
                      ),
                    );
                  },
                ),
              ],
            ),
            if (_rule.smoothingType != 'none') ...[
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      min: sliderMin,
                      max: sliderMax,
                      divisions: 99,
                      value: _rule.smoothing.clamp(sliderMin, sliderMax),
                      label: smoothingText,
                      onChanged:
                          (value) => _update(
                            _rule.copyWith(
                              smoothing:
                                  pointBased ? value.roundToDouble() : value,
                            ),
                          ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(smoothingText, textAlign: TextAlign.right),
                  ),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show original'),
                value: _rule.showOriginal,
                onChanged:
                    (value) => _update(_rule.copyWith(showOriginal: value)),
              ),
            ],
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
