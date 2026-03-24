import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/resource_refs.dart';
import '../../models/run_filters.dart';
import '../../providers/runs_providers.dart';

const _fieldOptions = <_FieldOption>[
  _FieldOption('tags', 'Tags', Icons.local_offer_outlined),
  _FieldOption('state', 'State', Icons.format_list_bulleted),
  _FieldOption('group', 'Group', Icons.folder_copy_outlined),
  _FieldOption('displayName', 'Display Name', Icons.text_fields),
  _FieldOption('name', 'Name', Icons.badge_outlined),
  _FieldOption('jobType', 'Job Type', Icons.work_outline),
  _FieldOption('username', 'Username', Icons.person_outline),
  _FieldOption('config.experiment_name', 'config.experiment_name', Icons.tune),
  _FieldOption('summary_metrics.loss', 'summary_metrics.loss', Icons.show_chart),
];

const _stateValues = <String>[
  'running',
  'finished',
  'crashed',
  'failed',
  'queued',
  'pending',
  'killed',
];

class RunFilterSheet extends ConsumerStatefulWidget {
  const RunFilterSheet({super.key, required this.projectRef});

  final ProjectRef projectRef;

  @override
  ConsumerState<RunFilterSheet> createState() => _RunFilterSheetState();
}

class _RunFilterSheetState extends ConsumerState<RunFilterSheet> {
  late List<RunFilterCondition> _draftConditions;
  bool _hasUnsupportedFilter = false;

  @override
  void initState() {
    super.initState();
    final filters = ref.read(runFiltersProvider(widget.projectRef));
    final extracted = _extractFlatConditions(filters.advancedFilterRoot);
    _draftConditions = extracted.conditions;
    _hasUnsupportedFilter = extracted.hasUnsupportedFilter;
    if (_draftConditions.isEmpty) {
      _draftConditions = [_defaultCondition()];
    }
  }

  bool get _canApply =>
      !_hasUnsupportedFilter &&
      _draftConditions.where((condition) => condition.isValid).isNotEmpty &&
      _draftConditions.every((condition) =>
          condition.fieldPath.trim().isEmpty ? condition.rawValue.trim().isEmpty : condition.isValid);

  void _apply() {
    if (!_canApply) return;
    final validConditions = _draftConditions
        .where((condition) => condition.fieldPath.trim().isNotEmpty)
        .toList(growable: false);
    final root = validConditions.isEmpty
        ? const RunFilterGroup.root()
        : RunFilterGroup(logic: RunFilterLogic.and, children: validConditions);
    ref.read(runFiltersProvider(widget.projectRef).notifier).applyAdvancedFilter(root);
    Navigator.pop(context);
  }

  void _clearAll() {
    setState(() {
      _hasUnsupportedFilter = false;
      _draftConditions = [_defaultCondition()];
    });
    ref.read(runFiltersProvider(widget.projectRef).notifier).clearAdvancedFilter();
  }

  void _addCondition() {
    setState(() {
      _draftConditions = [..._draftConditions, _defaultCondition()];
    });
  }

  void _updateCondition(int index, RunFilterCondition condition) {
    setState(() {
      _draftConditions = [
        for (var i = 0; i < _draftConditions.length; i++)
          if (i == index) condition else _draftConditions[i],
      ];
    });
  }

  void _removeCondition(int index) {
    setState(() {
      final next = [..._draftConditions]..removeAt(index);
      _draftConditions = next.isEmpty ? [_defaultCondition()] : next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCount = _draftConditions.where((condition) => condition.fieldPath.trim().isNotEmpty).length;

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
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.filter_list, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        const Text(
                          'Filter Runs',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              Text(
                'Add conditions like the W&B web app. All rows are combined with AND.',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    activeCount == 1 ? '1 filter' : '$activeCount filters',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _clearAll, child: const Text('Clear All')),
                ],
              ),
              if (_hasUnsupportedFilter)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Existing grouped/OR filters cannot be edited in this simplified view. Clear and rebuild them here.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              Expanded(
                child: _hasUnsupportedFilter
                    ? const SizedBox.shrink()
                    : ListView.separated(
                        itemCount: _draftConditions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _FilterRowCard(
                          key: ValueKey('filter-row-$index'),
                          condition: _draftConditions[index],
                          onChanged: (condition) => _updateCondition(index, condition),
                          onRemove: _draftConditions.length == 1 ? null : () => _removeCondition(index),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              if (!_hasUnsupportedFilter)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _addCondition,
                    icon: const Icon(Icons.add),
                    label: const Text('New filter'),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const Spacer(),
                  FilledButton(onPressed: _canApply ? _apply : null, child: const Text('Apply')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterRowCard extends StatelessWidget {
  const _FilterRowCard({
    super.key,
    required this.condition,
    required this.onChanged,
    this.onRemove,
  });

  final RunFilterCondition condition;
  final ValueChanged<RunFilterCondition> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final field = _FieldOption.forPath(condition.fieldPath);
    final operatorOptions = _operatorsForField(field);
    final effectiveOperator = operatorOptions.contains(condition.operator)
        ? condition.operator
        : operatorOptions.first;
    final effectiveValueType = effectiveOperator.allowedValueTypes.contains(condition.valueType)
        ? condition.valueType
        : _defaultValueTypeForField(field, effectiveOperator);
    final normalized = condition.copyWith(
      operator: effectiveOperator,
      valueType: effectiveValueType,
    );

    Widget valueInput;
    if (field.path == 'state') {
      valueInput = DropdownButtonFormField<String>(
        key: ValueKey('filter-state-${field.path}-${normalized.rawValue}'),
        value: _stateValues.contains(normalized.rawValue) ? normalized.rawValue : null,
        decoration: const InputDecoration(isDense: true),
        hint: const Text('Select state'),
        items: _stateValues
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(growable: false),
        onChanged: (value) => onChanged(normalized.copyWith(rawValue: value ?? '')),
      );
    } else {
      valueInput = TextFormField(
        key: ValueKey('filter-value-${field.path}'),
        initialValue: normalized.rawValue,
        decoration: InputDecoration(
          isDense: true,
          hintText: _hintForField(field, effectiveValueType),
        ),
        keyboardType: effectiveValueType == RunFilterValueType.number ||
                effectiveValueType == RunFilterValueType.numberList
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        onChanged: (value) => onChanged(normalized.copyWith(rawValue: value)),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_box_outline_blank, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'AND',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close),
                tooltip: 'Remove filter',
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              final fieldDropdown = _FieldDropdown(
                value: field,
                onChanged: (nextField) {
                  final nextOperator = _operatorsForField(nextField).first;
                  final nextValueType = _defaultValueTypeForField(nextField, nextOperator);
                  onChanged(
                    RunFilterCondition(
                      fieldPath: nextField.path,
                      operator: nextOperator,
                      valueType: nextValueType,
                      rawValue: '',
                    ),
                  );
                },
              );
              final operatorDropdown = _OperatorDropdown(
                field: field,
                value: effectiveOperator,
                onChanged: (operator) {
                  final nextValueType = _defaultValueTypeForField(field, operator);
                  onChanged(normalized.copyWith(operator: operator, valueType: nextValueType, rawValue: ''));
                },
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    fieldDropdown,
                    const SizedBox(height: 10),
                    operatorDropdown,
                    const SizedBox(height: 10),
                    valueInput,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 3, child: fieldDropdown),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: operatorDropdown),
                  const SizedBox(width: 12),
                  Expanded(flex: 5, child: valueInput),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FieldDropdown extends StatelessWidget {
  const _FieldDropdown({required this.value, required this.onChanged});

  final _FieldOption value;
  final ValueChanged<_FieldOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<_FieldOption>(
      value: value,
      decoration: const InputDecoration(isDense: true),
      items: _fieldOptions
          .map(
            (option) => DropdownMenuItem<_FieldOption>(
              value: option,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _OperatorDropdown extends StatelessWidget {
  const _OperatorDropdown({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final _FieldOption field;
  final RunFilterOperator value;
  final ValueChanged<RunFilterOperator> onChanged;

  @override
  Widget build(BuildContext context) {
    final operators = _operatorsForField(field);
    return DropdownButtonFormField<RunFilterOperator>(
      value: value,
      decoration: const InputDecoration(isDense: true),
      items: operators
          .map((operator) => DropdownMenuItem(value: operator, child: Text(_operatorLabel(operator))))
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _FieldOption {
  const _FieldOption(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;

  static _FieldOption forPath(String path) {
    return _fieldOptions.firstWhere(
      (option) => option.path == path,
      orElse: () => _fieldOptions.first,
    );
  }
}

({List<RunFilterCondition> conditions, bool hasUnsupportedFilter}) _extractFlatConditions(
  RunFilterGroup? root,
) {
  if (root == null) return (conditions: const <RunFilterCondition>[], hasUnsupportedFilter: false);
  if (root.logic != RunFilterLogic.and) {
    return (conditions: const <RunFilterCondition>[], hasUnsupportedFilter: true);
  }
  final conditions = <RunFilterCondition>[];
  for (final child in root.children) {
    if (child is RunFilterCondition) {
      conditions.add(child);
      continue;
    }
    return (conditions: const <RunFilterCondition>[], hasUnsupportedFilter: true);
  }
  return (conditions: conditions, hasUnsupportedFilter: false);
}


RunFilterCondition _defaultCondition() => const RunFilterCondition(
  fieldPath: 'tags',
  operator: RunFilterOperator.inList,
  valueType: RunFilterValueType.textList,
);

List<RunFilterOperator> _operatorsForField(_FieldOption field) {
  if (field.path == 'tags') {
    return const [RunFilterOperator.inList, RunFilterOperator.nin, RunFilterOperator.regex];
  }
  if (field.path == 'state') {
    return const [RunFilterOperator.eq, RunFilterOperator.ne];
  }
  if (field.path.startsWith('summary_metrics.')) {
    return const [RunFilterOperator.eq, RunFilterOperator.ne, RunFilterOperator.gt, RunFilterOperator.gte, RunFilterOperator.lt, RunFilterOperator.lte];
  }
  return const [RunFilterOperator.eq, RunFilterOperator.ne, RunFilterOperator.regex];
}

RunFilterValueType _defaultValueTypeForField(_FieldOption field, RunFilterOperator operator) {
  if (field.path == 'tags') {
    return RunFilterValueType.textList;
  }
  if (field.path == 'state') {
    return RunFilterValueType.text;
  }
  if (field.path.startsWith('summary_metrics.')) {
    if (operator == RunFilterOperator.eq || operator == RunFilterOperator.ne || operator == RunFilterOperator.gt || operator == RunFilterOperator.gte || operator == RunFilterOperator.lt || operator == RunFilterOperator.lte) {
      return RunFilterValueType.number;
    }
  }
  return operator.defaultValueType;
}

String _hintForField(_FieldOption field, RunFilterValueType valueType) {
  if (field.path == 'tags') return 'baseline, production';
  if (field.path == 'state') return 'running';
  return valueType.hintText;
}

String _operatorLabel(RunFilterOperator operator) {
  return switch (operator) {
    RunFilterOperator.eq => 'is',
    RunFilterOperator.ne => 'is not',
    RunFilterOperator.gt => '>',
    RunFilterOperator.gte => '>=',
    RunFilterOperator.lt => '<',
    RunFilterOperator.lte => '<=',
    RunFilterOperator.inList => 'contains any',
    RunFilterOperator.nin => 'contains none',
    RunFilterOperator.exists => 'exists',
    RunFilterOperator.regex => 'matches',
  };
}
