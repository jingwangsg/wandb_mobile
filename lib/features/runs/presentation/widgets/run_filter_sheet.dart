import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runs_providers.dart';

const _fieldSuggestions = <String>[
  'state',
  'displayName',
  'name',
  'group',
  'jobType',
  'tags',
  'username',
  'createdAt',
  'heartbeatAt',
  'config.experiment_name',
  'summary_metrics.loss',
];

class RunFilterSheet extends ConsumerStatefulWidget {
  const RunFilterSheet({super.key, required this.projectPath});

  final String projectPath;

  @override
  ConsumerState<RunFilterSheet> createState() => _RunFilterSheetState();
}

class _RunFilterSheetState extends ConsumerState<RunFilterSheet> {
  late RunFilterGroup _draftRoot;

  @override
  void initState() {
    super.initState();
    final filters = ref.read(runFiltersProvider(widget.projectPath));
    _draftRoot = filters.advancedFilterRoot ?? const RunFilterGroup.root();
  }

  bool get _canApply => _draftRoot.children.isEmpty || _draftRoot.isValid;

  void _apply() {
    if (!_canApply) return;
    ref
        .read(runFiltersProvider(widget.projectPath).notifier)
        .applyAdvancedFilter(_draftRoot);
    Navigator.pop(context);
  }

  void _clearAll() {
    setState(() {
      _draftRoot = const RunFilterGroup.root();
    });
    ref
        .read(runFiltersProvider(widget.projectPath).notifier)
        .clearAdvancedFilter();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filter Runs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                'Build nested filters for run fields, config.*, and summary_metrics.*.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    _draftRoot.conditionCount == 1
                        ? '1 condition'
                        : '${_draftRoot.conditionCount} conditions',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _clearAll,
                    child: const Text('Clear All'),
                  ),
                ],
              ),
              if (_draftRoot.children.isNotEmpty && !_draftRoot.isValid)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Fix incomplete conditions before applying filters.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  child: _FilterGroupCard(
                    pathId: 'root',
                    group: _draftRoot,
                    isRoot: true,
                    onChanged: (group) {
                      setState(() => _draftRoot = group);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _canApply ? _apply : null,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterGroupCard extends StatelessWidget {
  const _FilterGroupCard({
    required this.pathId,
    required this.group,
    required this.isRoot,
    required this.onChanged,
    this.onRemove,
  });

  final String pathId;
  final RunFilterGroup group;
  final bool isRoot;
  final ValueChanged<RunFilterGroup> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.only(left: isRoot ? 0 : 12, top: isRoot ? 0 : 12),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 480;
                final logicSelector = DropdownButtonFormField<RunFilterLogic>(
                  key: ValueKey('logic-$pathId-${group.logic.name}'),
                  value: group.logic,
                  decoration: const InputDecoration(
                    labelText: 'Logic',
                    isDense: true,
                  ),
                  items: RunFilterLogic.values
                      .map(
                        (logic) => DropdownMenuItem(
                          value: logic,
                          child: Text(logic.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (logic) {
                    if (logic == null) return;
                    onChanged(group.copyWith(logic: logic));
                  },
                );

                final removeButton =
                    onRemove == null
                        ? const SizedBox.shrink()
                        : IconButton(
                          key: ValueKey('remove-group-$pathId'),
                          onPressed: onRemove,
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove group',
                        );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GroupTitle(
                        title: isRoot ? 'Root Group' : 'Nested Group',
                        subtitle:
                            'Combine child conditions with ${group.logic.label}.',
                      ),
                      const SizedBox(height: 12),
                      logicSelector,
                      if (onRemove != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: removeButton,
                        ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _GroupTitle(
                        title: isRoot ? 'Root Group' : 'Nested Group',
                        subtitle:
                            'Combine child conditions with ${group.logic.label}.',
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(width: 160, child: logicSelector),
                    if (onRemove != null) removeButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('add-condition-$pathId'),
                  onPressed: () {
                    onChanged(
                      group.copyWith(
                        children: [
                          ...group.children,
                          const RunFilterCondition(),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Condition'),
                ),
                OutlinedButton.icon(
                  key: ValueKey('add-group-$pathId'),
                  onPressed: () {
                    onChanged(
                      group.copyWith(
                        children: [
                          ...group.children,
                          const RunFilterGroup.root(),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('Group'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (group.children.isEmpty)
              Text(
                'No conditions yet. Add a condition or nested group.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white60,
                ),
              )
            else
              Column(
                children: [
                  for (var index = 0; index < group.children.length; index++)
                    _buildChild(
                      context,
                      child: group.children[index],
                      index: index,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChild(
    BuildContext context, {
    required RunFilterNode child,
    required int index,
  }) {
    final childPathId = '$pathId-$index';

    void updateChild(RunFilterNode nextChild) {
      final nextChildren = [...group.children];
      nextChildren[index] = nextChild;
      onChanged(group.copyWith(children: nextChildren));
    }

    void removeChild() {
      final nextChildren = [...group.children]..removeAt(index);
      onChanged(group.copyWith(children: nextChildren));
    }

    if (child is RunFilterGroup) {
      return _FilterGroupCard(
        pathId: childPathId,
        group: child,
        isRoot: false,
        onChanged: updateChild,
        onRemove: removeChild,
      );
    }

    return _ConditionEditor(
      key: ValueKey('condition-$childPathId'),
      pathId: childPathId,
      condition: child as RunFilterCondition,
      onChanged: updateChild,
      onRemove: removeChild,
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.white60),
        ),
      ],
    );
  }
}

class _ConditionEditor extends StatefulWidget {
  const _ConditionEditor({
    super.key,
    required this.pathId,
    required this.condition,
    required this.onChanged,
    required this.onRemove,
  });

  final String pathId;
  final RunFilterCondition condition;
  final ValueChanged<RunFilterCondition> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ConditionEditor> createState() => _ConditionEditorState();
}

class _ConditionEditorState extends State<_ConditionEditor> {
  late final TextEditingController _fieldController;
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _fieldController = TextEditingController(text: widget.condition.fieldPath);
    _valueController = TextEditingController(text: widget.condition.rawValue);
  }

  @override
  void didUpdateWidget(covariant _ConditionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_fieldController.text != widget.condition.fieldPath) {
      _fieldController.value = TextEditingValue(
        text: widget.condition.fieldPath,
        selection: TextSelection.collapsed(
          offset: widget.condition.fieldPath.length,
        ),
      );
    }
    if (_valueController.text != widget.condition.rawValue) {
      _valueController.value = TextEditingValue(
        text: widget.condition.rawValue,
        selection: TextSelection.collapsed(
          offset: widget.condition.rawValue.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _fieldController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final condition = widget.condition;
    final suggestions = _matchingSuggestions(condition.fieldPath);

    return Card(
      margin: const EdgeInsets.only(left: 12, top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Condition',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: ValueKey('remove-condition-${widget.pathId}'),
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove condition',
                ),
              ],
            ),
            TextField(
              key: ValueKey('field-${widget.pathId}'),
              controller: _fieldController,
              onChanged: (value) {
                widget.onChanged(condition.copyWith(fieldPath: value));
              },
              decoration: const InputDecoration(
                labelText: 'Field path',
                hintText: 'state, tags, config.lr, summary_metrics.loss',
              ),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final suggestion in suggestions)
                    ActionChip(
                      label: Text(suggestion),
                      onPressed: () {
                        _fieldController.value = TextEditingValue(
                          text: suggestion,
                          selection: TextSelection.collapsed(
                            offset: suggestion.length,
                          ),
                        );
                        widget.onChanged(
                          condition.copyWith(fieldPath: suggestion),
                        );
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final operatorField =
                    DropdownButtonFormField<RunFilterOperator>(
                      key: ValueKey(
                        'operator-${widget.pathId}-${condition.operator.name}',
                      ),
                      value: condition.operator,
                      decoration: const InputDecoration(
                        labelText: 'Operator',
                        isDense: true,
                      ),
                      items: RunFilterOperator.values
                          .map(
                            (operator) => DropdownMenuItem(
                              value: operator,
                              child: Text(operator.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (operator) {
                        if (operator == null) return;
                        final valueType =
                            operator.allowedValueTypes.contains(
                                  condition.valueType,
                                )
                                ? condition.valueType
                                : operator.defaultValueType;
                        widget.onChanged(
                          condition.copyWith(
                            operator: operator,
                            valueType: valueType,
                            rawValue: _normalizedRawValue(
                              valueType,
                              condition.rawValue,
                            ),
                          ),
                        );
                      },
                    );

                final valueTypeField = DropdownButtonFormField<
                  RunFilterValueType
                >(
                  key: ValueKey(
                    'value-type-${widget.pathId}-${condition.valueType.name}',
                  ),
                  value: condition.valueType,
                  decoration: const InputDecoration(
                    labelText: 'Value Type',
                    isDense: true,
                  ),
                  items: condition.operator.allowedValueTypes
                      .map(
                        (valueType) => DropdownMenuItem(
                          value: valueType,
                          child: Text(valueType.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (valueType) {
                    if (valueType == null) return;
                    widget.onChanged(
                      condition.copyWith(
                        valueType: valueType,
                        rawValue: _normalizedRawValue(
                          valueType,
                          condition.rawValue,
                        ),
                      ),
                    );
                  },
                );

                if (compact) {
                  return Column(
                    children: [
                      operatorField,
                      const SizedBox(height: 12),
                      valueTypeField,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: operatorField),
                    const SizedBox(width: 12),
                    Expanded(child: valueTypeField),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _ConditionValueField(
              pathId: widget.pathId,
              condition: condition,
              controller: _valueController,
              onChanged: (rawValue) {
                widget.onChanged(condition.copyWith(rawValue: rawValue));
              },
            ),
            if (condition.validationError != null) ...[
              const SizedBox(height: 8),
              Text(
                condition.validationError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _matchingSuggestions(String query) {
    final trimmed = query.trim().toLowerCase();
    final matches =
        trimmed.isEmpty
            ? _fieldSuggestions
            : _fieldSuggestions.where(
              (suggestion) => suggestion.toLowerCase().contains(trimmed),
            );
    return matches.take(6).toList(growable: false);
  }

  String _normalizedRawValue(RunFilterValueType valueType, String rawValue) {
    if (valueType == RunFilterValueType.boolean) {
      return rawValue == 'false' ? 'false' : 'true';
    }
    return rawValue;
  }
}

class _ConditionValueField extends StatelessWidget {
  const _ConditionValueField({
    required this.pathId,
    required this.condition,
    required this.controller,
    required this.onChanged,
  });

  final String pathId;
  final RunFilterCondition condition;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (condition.valueType == RunFilterValueType.boolean) {
      return DropdownButtonFormField<String>(
        key: ValueKey('value-$pathId-${condition.rawValue}'),
        value: condition.rawValue == 'false' ? 'false' : 'true',
        decoration: InputDecoration(
          labelText:
              condition.operator == RunFilterOperator.exists
                  ? 'Exists'
                  : condition.valueType.inputLabel,
        ),
        items: const [
          DropdownMenuItem(value: 'true', child: Text('true')),
          DropdownMenuItem(value: 'false', child: Text('false')),
        ],
        onChanged: (value) {
          if (value == null) return;
          onChanged(value);
        },
      );
    }

    final isListValue =
        condition.valueType == RunFilterValueType.textList ||
        condition.valueType == RunFilterValueType.numberList;

    final keyboardType = switch (condition.valueType) {
      RunFilterValueType.number || RunFilterValueType.numberList =>
        const TextInputType.numberWithOptions(decimal: true, signed: true),
      _ => TextInputType.text,
    };

    return TextField(
      key: ValueKey('value-$pathId'),
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters:
          condition.valueType == RunFilterValueType.datetime
              ? [FilteringTextInputFormatter.singleLineFormatter]
              : null,
      minLines: isListValue ? 2 : 1,
      maxLines: isListValue ? 2 : 1,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: condition.valueType.inputLabel,
        hintText: condition.valueType.hintText,
        helperText: switch (condition.valueType) {
          RunFilterValueType.datetime => 'Stored as UTC ISO-8601.',
          RunFilterValueType.textList ||
          RunFilterValueType.numberList => 'Separate values with commas.',
          _ => null,
        },
      ),
    );
  }
}
