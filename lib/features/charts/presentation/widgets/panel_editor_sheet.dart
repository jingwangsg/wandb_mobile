import 'package:flutter/material.dart';

import '../../../../core/widgets/wandb_icon.dart';
import '../../models/metric_expression.dart';
import '../../models/panel_spec.dart';
import 'key_picker.dart';

/// Creates or edits an app panel: title, metrics, a metric regex, and
/// expressions, mirroring the web's Data and Expressions tabs.
class PanelEditorSheet extends StatefulWidget {
  const PanelEditorSheet({
    super.key,
    required this.catalog,
    required this.onSave,
    this.initial,
    this.onDelete,
  });

  /// Metric keys offered for selection.
  final List<String> catalog;
  final PanelSpec? initial;
  final ValueChanged<PanelSpec> onSave;
  final VoidCallback? onDelete;

  @override
  State<PanelEditorSheet> createState() => _PanelEditorSheetState();
}

class _PanelEditorSheetState extends State<PanelEditorSheet> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _regex = TextEditingController(
    text: widget.initial?.metricRegex ?? '',
  );
  late final _metrics = [...?widget.initial?.metrics];
  late final _expressions = [
    for (final source in widget.initial?.expressions ?? const <String>[])
      TextEditingController(text: source),
  ];

  @override
  void dispose() {
    _title.dispose();
    _regex.dispose();
    for (final controller in _expressions) {
      controller.dispose();
    }
    super.dispose();
  }

  String? get _regexError {
    if (_regex.text.isEmpty) return null;
    try {
      RegExp(_regex.text);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _expressionError(String source) {
    if (source.trim().isEmpty) return null;
    try {
      MetricExpression.parse(source);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  late final _id =
      widget.initial?.id ?? 'panel-${DateTime.now().microsecondsSinceEpoch}';

  PanelSpec get _spec => PanelSpec(
    id: _id,
    section: widget.initial?.section ?? 'Custom',
    title: _title.text.trim(),
    metrics: _metrics,
    metricRegex: _regex.text.isEmpty ? null : _regex.text,
    expressions: [
      for (final controller in _expressions)
        if (controller.text.trim().isNotEmpty) controller.text.trim(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final expressionErrors = [
      for (final controller in _expressions) _expressionError(controller.text),
    ];
    final spec = _spec;
    final canSave =
        _regexError == null &&
        expressionErrors.every((error) => error == null) &&
        (spec.metrics.isNotEmpty ||
            spec.metricRegex != null ||
            spec.expressions.isNotEmpty);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.initial == null ? 'New panel' : 'Edit panel',
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
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Chart title',
                hintText: 'Metric names when empty',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('Y axis', style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final metric in _metrics)
                  InputChip(
                    label: Text(metric),
                    onDeleted: () => setState(() => _metrics.remove(metric)),
                  ),
                ActionChip(
                  avatar: const WandbIcon('add_(new)', size: 16),
                  label: const Text('Add metric'),
                  onPressed:
                      () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder:
                            (_) => KeyPicker(
                              title: 'Metric',
                              options: [
                                for (final key in widget.catalog)
                                  if (!_metrics.contains(key)) key,
                              ],
                              onSelected:
                                  (key) => setState(() => _metrics.add(key)),
                            ),
                      ),
                ),
              ],
            ),
            TextField(
              controller: _regex,
              decoration: InputDecoration(
                labelText: 'Metric regex',
                hintText: r'e.g. train/.*_loss',
                errorText: _regexError,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('Expressions', style: Theme.of(context).textTheme.titleSmall),
            for (final (index, controller) in _expressions.indexed)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: r'${train/loss} - ${train/loss:min}',
                        errorText: expressionErrors[index],
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove expression',
                    onPressed:
                        () => setState(
                          () => _expressions.removeAt(index).dispose(),
                        ),
                    icon: const WandbIcon('delete', size: 18),
                  ),
                ],
              ),
            TextButton.icon(
              onPressed:
                  () =>
                      setState(() => _expressions.add(TextEditingController())),
              icon: const WandbIcon('add_(new)', size: 16),
              label: const Text('Add expression'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.onDelete != null)
                  TextButton(
                    onPressed: () {
                      widget.onDelete!();
                      Navigator.pop(context);
                    },
                    child: const Text('Delete panel'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed:
                      canSave
                          ? () {
                            widget.onSave(spec);
                            Navigator.pop(context);
                          }
                          : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
