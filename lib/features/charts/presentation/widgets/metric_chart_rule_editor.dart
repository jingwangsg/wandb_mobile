import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../models/metric_chart_rule.dart';

/// Reusable rule editor form for metric charts.
/// Used inline in [ExpandedChartScreen] and wrapped in a bottom sheet elsewhere.
class MetricChartRuleEditor extends StatefulWidget {
  const MetricChartRuleEditor({
    super.key,
    required this.metricKey,
    required this.initialRule,
    required this.onApply,
    this.onCancel,
  });

  final String metricKey;
  final MetricChartRule initialRule;
  final ValueChanged<MetricChartRule> onApply;
  final VoidCallback? onCancel;

  @override
  State<MetricChartRuleEditor> createState() => _MetricChartRuleEditorState();
}

class _MetricChartRuleEditorState extends State<MetricChartRuleEditor> {
  late double _smoothing;
  late bool _useAutoMin;
  late bool _useAutoMax;
  late bool _useAutoXMin;
  late bool _useAutoXMax;
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  late final TextEditingController _xMinController;
  late final TextEditingController _xMaxController;

  @override
  void initState() {
    super.initState();
    _smoothing = widget.initialRule.smoothing;
    _useAutoMin = widget.initialRule.useAutoMin;
    _useAutoMax = widget.initialRule.useAutoMax;
    _useAutoXMin = widget.initialRule.useAutoXMin;
    _useAutoXMax = widget.initialRule.useAutoXMax;
    _minController = TextEditingController(
      text: widget.initialRule.min?.toString() ?? '',
    );
    _maxController = TextEditingController(
      text: widget.initialRule.max?.toString() ?? '',
    );
    _xMinController = TextEditingController(
      text: widget.initialRule.xMin?.toString() ?? '',
    );
    _xMaxController = TextEditingController(
      text: widget.initialRule.xMax?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    _xMinController.dispose();
    _xMaxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final validationError = _validationError;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.metricKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'JetBrains Mono',
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tune smoothing, Y-axis and X-axis bounds for this chart only.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Text('Smoothing'),
            Expanded(
              child: Slider(
                value: _smoothing,
                min: 0,
                max: 0.99,
                divisions: 99,
                label: _smoothing.toStringAsFixed(2),
                onChanged: (value) => setState(() => _smoothing = value),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                _smoothing.toStringAsFixed(2),
                style: const TextStyle(fontFamily: 'JetBrains Mono'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AxisOverrideField(
          label: 'Y Min',
          autoValue: _useAutoMin,
          controller: _minController,
          onAutoChanged: (value) => setState(() => _useAutoMin = value),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _AxisOverrideField(
          label: 'Y Max',
          autoValue: _useAutoMax,
          controller: _maxController,
          onAutoChanged: (value) => setState(() => _useAutoMax = value),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _AxisOverrideField(
          label: 'X Min',
          autoValue: _useAutoXMin,
          controller: _xMinController,
          onAutoChanged: (value) => setState(() => _useAutoXMin = value),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _AxisOverrideField(
          label: 'X Max',
          autoValue: _useAutoXMax,
          controller: _xMaxController,
          onAutoChanged: (value) => setState(() => _useAutoXMax = value),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (validationError != null)
          Text(
            validationError,
            style: const TextStyle(color: WandbColors.failed, fontSize: 12),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _smoothing = MetricChartRule.defaults.smoothing;
                  _useAutoMin = true;
                  _useAutoMax = true;
                  _useAutoXMin = true;
                  _useAutoXMax = true;
                  _minController.clear();
                  _maxController.clear();
                  _xMinController.clear();
                  _xMaxController.clear();
                });
              },
              child: const Text('Reset'),
            ),
            const Spacer(),
            if (widget.onCancel != null)
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  validationError == null
                      ? () => widget.onApply(_currentRule)
                      : null,
              child: const Text('Apply'),
            ),
          ],
        ),
      ],
    );
  }

  MetricChartRule get _currentRule {
    return MetricChartRule(
      smoothing: _smoothing,
      useAutoMin: _useAutoMin,
      min: _parsedValue(_minController.text),
      useAutoMax: _useAutoMax,
      max: _parsedValue(_maxController.text),
      useAutoXMin: _useAutoXMin,
      xMin: _parsedValue(_xMinController.text),
      useAutoXMax: _useAutoXMax,
      xMax: _parsedValue(_xMaxController.text),
    );
  }

  String? get _validationError {
    final min = _useAutoMin ? null : _parsedValue(_minController.text);
    final max = _useAutoMax ? null : _parsedValue(_maxController.text);
    final xMin = _useAutoXMin ? null : _parsedValue(_xMinController.text);
    final xMax = _useAutoXMax ? null : _parsedValue(_xMaxController.text);

    if (!_useAutoMin && min == null) {
      return 'Y min must be a valid number.';
    }
    if (!_useAutoMax && max == null) {
      return 'Y max must be a valid number.';
    }
    if (min != null && max != null && min >= max) {
      return 'Y min must be smaller than Y max.';
    }
    if (!_useAutoXMin && xMin == null) {
      return 'X min must be a valid number.';
    }
    if (!_useAutoXMax && xMax == null) {
      return 'X max must be a valid number.';
    }
    if (xMin != null && xMax != null && xMin >= xMax) {
      return 'X min must be smaller than X max.';
    }
    return null;
  }

  double? _parsedValue(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }
}

class _AxisOverrideField extends StatelessWidget {
  const _AxisOverrideField({
    required this.label,
    required this.autoValue,
    required this.controller,
    required this.onAutoChanged,
    required this.onChanged,
  });

  final String label;
  final bool autoValue;
  final TextEditingController controller;
  final ValueChanged<bool> onAutoChanged;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !autoValue,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: label,
              hintText: autoValue ? 'Auto' : 'Enter a number',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Auto', style: TextStyle(fontSize: 12)),
            Switch(value: autoValue, onChanged: onAutoChanged),
          ],
        ),
      ],
    );
  }
}
