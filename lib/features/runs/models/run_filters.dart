enum RunFilterLogic { and, or, nor }

extension RunFilterLogicX on RunFilterLogic {
  String get apiKey => switch (this) {
    RunFilterLogic.and => r'$and',
    RunFilterLogic.or => r'$or',
    RunFilterLogic.nor => r'$nor',
  };

  String get label => switch (this) {
    RunFilterLogic.and => 'AND',
    RunFilterLogic.or => 'OR',
    RunFilterLogic.nor => 'NOR',
  };
}

enum RunFilterOperator { eq, ne, gt, gte, lt, lte, inList, nin, exists, regex }

extension RunFilterOperatorX on RunFilterOperator {
  String get apiKey => switch (this) {
    RunFilterOperator.eq => r'$eq',
    RunFilterOperator.ne => r'$ne',
    RunFilterOperator.gt => r'$gt',
    RunFilterOperator.gte => r'$gte',
    RunFilterOperator.lt => r'$lt',
    RunFilterOperator.lte => r'$lte',
    RunFilterOperator.inList => r'$in',
    RunFilterOperator.nin => r'$nin',
    RunFilterOperator.exists => r'$exists',
    RunFilterOperator.regex => r'$regex',
  };

  String get label => switch (this) {
    RunFilterOperator.eq => 'Equals',
    RunFilterOperator.ne => 'Not equals',
    RunFilterOperator.gt => 'Greater than',
    RunFilterOperator.gte => 'Greater or equal',
    RunFilterOperator.lt => 'Less than',
    RunFilterOperator.lte => 'Less or equal',
    RunFilterOperator.inList => 'In list',
    RunFilterOperator.nin => 'Not in list',
    RunFilterOperator.exists => 'Exists',
    RunFilterOperator.regex => 'Regex',
  };

  List<RunFilterValueType> get allowedValueTypes => switch (this) {
    RunFilterOperator.eq || RunFilterOperator.ne => [
      RunFilterValueType.text,
      RunFilterValueType.number,
      RunFilterValueType.boolean,
      RunFilterValueType.datetime,
    ],
    RunFilterOperator.gt ||
    RunFilterOperator.gte ||
    RunFilterOperator.lt ||
    RunFilterOperator
        .lte => [RunFilterValueType.number, RunFilterValueType.datetime],
    RunFilterOperator.inList || RunFilterOperator.nin => [
      RunFilterValueType.textList,
      RunFilterValueType.numberList,
    ],
    RunFilterOperator.exists => [RunFilterValueType.boolean],
    RunFilterOperator.regex => [RunFilterValueType.text],
  };

  RunFilterValueType get defaultValueType => allowedValueTypes.first;
}

enum RunFilterValueType {
  text,
  number,
  boolean,
  datetime,
  textList,
  numberList,
}

extension RunFilterValueTypeX on RunFilterValueType {
  String get label => switch (this) {
    RunFilterValueType.text => 'Text',
    RunFilterValueType.number => 'Number',
    RunFilterValueType.boolean => 'Boolean',
    RunFilterValueType.datetime => 'DateTime',
    RunFilterValueType.textList => 'Text List',
    RunFilterValueType.numberList => 'Number List',
  };

  String get inputLabel => switch (this) {
    RunFilterValueType.text => 'Value',
    RunFilterValueType.number => 'Number',
    RunFilterValueType.boolean => 'Boolean',
    RunFilterValueType.datetime => 'DateTime (ISO-8601)',
    RunFilterValueType.textList => 'Values (comma-separated)',
    RunFilterValueType.numberList => 'Numbers (comma-separated)',
  };

  String get hintText => switch (this) {
    RunFilterValueType.text => 'finished',
    RunFilterValueType.number => '0.5',
    RunFilterValueType.boolean => 'true',
    RunFilterValueType.datetime => '2024-01-01T00:00:00Z',
    RunFilterValueType.textList => 'baseline, production',
    RunFilterValueType.numberList => '0.1, 0.2, 0.5',
  };
}

abstract class RunFilterNode {
  const RunFilterNode();

  int get conditionCount;
  bool get isValid;
  Map<String, dynamic>? toApiFilter();
}

class RunFilterGroup extends RunFilterNode {
  const RunFilterGroup({required this.logic, this.children = const []});

  const RunFilterGroup.root() : logic = RunFilterLogic.and, children = const [];

  final RunFilterLogic logic;
  final List<RunFilterNode> children;

  @override
  int get conditionCount =>
      children.fold(0, (count, child) => count + child.conditionCount);

  @override
  bool get isValid =>
      children.isNotEmpty && children.every((child) => child.isValid);

  @override
  Map<String, dynamic>? toApiFilter() {
    if (!isValid) return null;
    final serializedChildren = children
        .map((child) => child.toApiFilter())
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    if (serializedChildren.isEmpty) return null;
    if (serializedChildren.length == 1) return serializedChildren.first;
    return {logic.apiKey: serializedChildren};
  }

  RunFilterGroup copyWith({
    RunFilterLogic? logic,
    List<RunFilterNode>? children,
  }) {
    return RunFilterGroup(
      logic: logic ?? this.logic,
      children: children ?? this.children,
    );
  }
}

class RunFilterCondition extends RunFilterNode {
  const RunFilterCondition({
    this.fieldPath = '',
    this.operator = RunFilterOperator.eq,
    this.valueType = RunFilterValueType.text,
    this.rawValue = '',
  });

  final String fieldPath;
  final RunFilterOperator operator;
  final RunFilterValueType valueType;
  final String rawValue;

  @override
  int get conditionCount => 1;

  @override
  bool get isValid => validationError == null;

  @override
  Map<String, dynamic>? toApiFilter() {
    if (!isValid) return null;

    final field = fieldPath.trim();
    final parsedValue = _parsedValue();
    if (parsedValue == null) return null;

    return switch (operator) {
      RunFilterOperator.eq => {field: parsedValue},
      RunFilterOperator.ne => {
        field: {RunFilterOperator.ne.apiKey: parsedValue},
      },
      RunFilterOperator.gt => {
        field: {RunFilterOperator.gt.apiKey: parsedValue},
      },
      RunFilterOperator.gte => {
        field: {RunFilterOperator.gte.apiKey: parsedValue},
      },
      RunFilterOperator.lt => {
        field: {RunFilterOperator.lt.apiKey: parsedValue},
      },
      RunFilterOperator.lte => {
        field: {RunFilterOperator.lte.apiKey: parsedValue},
      },
      RunFilterOperator.inList => {
        field: {RunFilterOperator.inList.apiKey: parsedValue},
      },
      RunFilterOperator.nin => {
        field: {RunFilterOperator.nin.apiKey: parsedValue},
      },
      RunFilterOperator.exists => {
        field: {RunFilterOperator.exists.apiKey: parsedValue},
      },
      RunFilterOperator.regex => {
        field: {RunFilterOperator.regex.apiKey: parsedValue},
      },
    };
  }

  String? get validationError {
    if (fieldPath.trim().isEmpty) {
      return 'Field path is required.';
    }
    if (!operator.allowedValueTypes.contains(valueType)) {
      return '${operator.label} does not support ${valueType.label}.';
    }
    if (_parsedValue() == null) {
      return switch (valueType) {
        RunFilterValueType.text => 'Text value is required.',
        RunFilterValueType.number => 'Enter a valid number.',
        RunFilterValueType.boolean => 'Select true or false.',
        RunFilterValueType.datetime => 'Enter a valid ISO-8601 date/time.',
        RunFilterValueType.textList => 'Enter at least one list value.',
        RunFilterValueType.numberList =>
          'Enter one or more comma-separated numbers.',
      };
    }
    return null;
  }

  RunFilterCondition copyWith({
    String? fieldPath,
    RunFilterOperator? operator,
    RunFilterValueType? valueType,
    String? rawValue,
  }) {
    return RunFilterCondition(
      fieldPath: fieldPath ?? this.fieldPath,
      operator: operator ?? this.operator,
      valueType: valueType ?? this.valueType,
      rawValue: rawValue ?? this.rawValue,
    );
  }

  dynamic _parsedValue() {
    final trimmedValue = rawValue.trim();
    switch (valueType) {
      case RunFilterValueType.text:
        return trimmedValue.isEmpty ? null : trimmedValue;
      case RunFilterValueType.number:
        return num.tryParse(trimmedValue);
      case RunFilterValueType.boolean:
        if (trimmedValue == 'true') return true;
        if (trimmedValue == 'false') return false;
        return null;
      case RunFilterValueType.datetime:
        final parsed = DateTime.tryParse(trimmedValue);
        return parsed?.toUtc().toIso8601String();
      case RunFilterValueType.textList:
        final values = trimmedValue
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        return values.isEmpty ? null : values;
      case RunFilterValueType.numberList:
        final parts = trimmedValue
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        if (parts.isEmpty) return null;
        final values = parts.map(num.tryParse).toList(growable: false);
        if (values.any((value) => value == null)) return null;
        return values.whereType<num>().toList(growable: false);
    }
  }
}

class RunFilters {
  const RunFilters({
    this.order = '-created_at',
    this.searchQuery,
    this.advancedFilterRoot,
  });

  final String order;
  final String? searchQuery;
  final RunFilterGroup? advancedFilterRoot;

  String? get normalizedSearchQuery {
    final value = searchQuery?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  bool get hasSearchQuery => normalizedSearchQuery != null;
  int get advancedFilterCount => advancedFilterRoot?.conditionCount ?? 0;
  bool get hasAdvancedFilters => advancedFilterCount > 0;

  Map<String, dynamic>? toApiFilters() {
    final conditions = <Map<String, dynamic>>[];

    if (normalizedSearchQuery != null) {
      conditions.add({
        'displayName': {r'$regex': normalizedSearchQuery},
      });
    }

    final advancedFilters = advancedFilterRoot?.toApiFilter();
    if (advancedFilters != null) {
      conditions.add(advancedFilters);
    }

    if (conditions.isEmpty) return null;
    if (conditions.length == 1) return conditions.first;
    return {r'$and': conditions};
  }

  RunFilters copyWith({
    String? order,
    String? searchQuery,
    RunFilterGroup? advancedFilterRoot,
    bool clearSearchQuery = false,
    bool clearAdvancedFilter = false,
  }) {
    return RunFilters(
      order: order ?? this.order,
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      advancedFilterRoot:
          clearAdvancedFilter
              ? null
              : (advancedFilterRoot ?? this.advancedFilterRoot),
    );
  }
}
