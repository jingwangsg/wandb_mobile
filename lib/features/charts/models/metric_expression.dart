import 'dart:math' as math;

import '../../../core/models/metric_point.dart';

/// Evaluates [expression] at every point of its first metric, reading the
/// other metrics at the same axis position (they come from one request, so
/// bucket positions match) and aggregates over each metric's whole series.
MetricSeries expressionSeries(
  MetricExpression expression,
  List<MetricSeries> fetched,
) {
  final byKey = {for (final series in fetched) series.key: series};
  final first = byKey[expression.keys.first];
  if (first == null) return MetricSeries(key: expression.source, points: []);
  final lookup = {
    for (final key in expression.keys)
      key: {
        for (final point in byKey[key]?.points ?? const <MetricPoint>[])
          (point.x ?? point.step).toDouble(): point.value,
      },
  };
  double? aggregate(String key, String name) {
    final values = byKey[key]?.points.map((point) => point.value).toList();
    if (values == null || values.isEmpty) return null;
    return switch (name) {
      'min' => values.reduce(math.min),
      'max' => values.reduce(math.max),
      'avg' => values.reduce((a, b) => a + b) / values.length,
      'first' => values.first,
      _ => values.last,
    };
  }

  final points = <MetricPoint>[];
  for (final point in first.points) {
    final x = (point.x ?? point.step).toDouble();
    final value = expression.evaluate(
      (key, name) => name == null ? (lookup[key]?[x]) : aggregate(key, name),
    );
    if (value != null) {
      points.add(
        MetricPoint(
          step: point.step,
          value: value,
          timestamp: point.timestamp,
          x: point.x,
        ),
      );
    }
  }
  return MetricSeries(key: expression.source, points: points);
}

/// A web panel expression such as `${train/loss} - ${train/loss:min}`:
/// `${key}` reads a metric at the current point, `${key:min|max|avg|first|last}`
/// an aggregate over the run, combined with `+ - * / ^` and parentheses.
class MetricExpression {
  MetricExpression._(this.source, this._root, this.keys);

  final String source;
  final _Node _root;

  /// Every metric the expression reads.
  final Set<String> keys;

  /// Throws [FormatException] on a malformed expression.
  factory MetricExpression.parse(String source) {
    final parser = _Parser(source);
    final root = parser.expression();
    if (parser._index < parser._tokens.length) {
      throw FormatException('Unexpected "${parser._tokens[parser._index]}"');
    }
    return MetricExpression._(source, root, parser.keys);
  }

  /// Null when any referenced value is missing or the result is not finite.
  double? evaluate(double? Function(String key, String? aggregate) resolve) {
    final value = _root.evaluate(resolve);
    return value != null && value.isFinite ? value : null;
  }
}

sealed class _Node {
  double? evaluate(double? Function(String key, String? aggregate) resolve);
}

class _Number extends _Node {
  _Number(this.value);
  final double value;
  @override
  double? evaluate(double? Function(String, String?) resolve) => value;
}

class _Reference extends _Node {
  _Reference(this.key, this.aggregate);
  final String key;
  final String? aggregate;
  @override
  double? evaluate(double? Function(String, String?) resolve) =>
      resolve(key, aggregate);
}

class _Binary extends _Node {
  _Binary(this.operator, this.left, this.right);
  final String operator;
  final _Node left;
  final _Node right;
  @override
  double? evaluate(double? Function(String, String?) resolve) {
    final a = left.evaluate(resolve);
    final b = right.evaluate(resolve);
    if (a == null || b == null) return null;
    return switch (operator) {
      '+' => a + b,
      '-' => a - b,
      '*' => a * b,
      '/' => a / b,
      _ => math.pow(a, b).toDouble(),
    };
  }
}

class _Negate extends _Node {
  _Negate(this.inner);
  final _Node inner;
  @override
  double? evaluate(double? Function(String, String?) resolve) {
    final value = inner.evaluate(resolve);
    return value == null ? null : -value;
  }
}

class _Parser {
  _Parser(String source) : _tokens = _tokenize(source);

  final List<String> _tokens;
  final keys = <String>{};
  var _index = 0;

  static final _token = RegExp(
    r'\$\{[^}]*\}|\d+(?:\.\d+)?(?:[eE][-+]?\d+)?|[-+*/^()]',
  );

  static List<String> _tokenize(String source) {
    final tokens = <String>[];
    var position = 0;
    for (final match in _token.allMatches(source)) {
      if (source.substring(position, match.start).trim().isNotEmpty) {
        throw FormatException(
          'Unexpected "${source.substring(position, match.start).trim()}"',
        );
      }
      tokens.add(match.group(0)!);
      position = match.end;
    }
    if (source.substring(position).trim().isNotEmpty) {
      throw FormatException(
        'Unexpected "${source.substring(position).trim()}"',
      );
    }
    if (tokens.isEmpty) throw const FormatException('Empty expression');
    return tokens;
  }

  String? get _current => _index < _tokens.length ? _tokens[_index] : null;

  _Node expression() {
    var node = _term();
    while (_current == '+' || _current == '-') {
      final operator = _tokens[_index++];
      node = _Binary(operator, node, _term());
    }
    return node;
  }

  _Node _term() {
    var node = _power();
    while (_current == '*' || _current == '/') {
      final operator = _tokens[_index++];
      node = _Binary(operator, node, _power());
    }
    return node;
  }

  _Node _power() {
    final base = _unary();
    if (_current == '^') {
      _index++;
      return _Binary('^', base, _power());
    }
    return base;
  }

  _Node _unary() {
    if (_current == '-') {
      _index++;
      return _Negate(_unary());
    }
    if (_current == '+') {
      _index++;
      return _unary();
    }
    return _primary();
  }

  _Node _primary() {
    final token = _current;
    if (token == null) throw const FormatException('Expression ends early');
    _index++;
    if (token == '(') {
      final inner = expression();
      if (_current != ')') throw const FormatException('Missing ")"');
      _index++;
      return inner;
    }
    if (token.startsWith(r'${')) {
      final body = token.substring(2, token.length - 1);
      final colon = body.lastIndexOf(':');
      final key = colon > 0 ? body.substring(0, colon) : body;
      final aggregate = colon > 0 ? body.substring(colon + 1) : null;
      if (key.isEmpty) throw const FormatException('Empty metric reference');
      if (aggregate != null &&
          !const {'min', 'max', 'avg', 'first', 'last'}.contains(aggregate)) {
        throw FormatException('Unknown aggregate ":$aggregate"');
      }
      keys.add(key);
      return _Reference(key, aggregate);
    }
    final number = double.tryParse(token);
    if (number == null) throw FormatException('Unexpected "$token"');
    return _Number(number);
  }
}
