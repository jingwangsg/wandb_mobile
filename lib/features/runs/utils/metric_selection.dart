import 'dart:math' as math;

import '../../../core/models/metric_point.dart';

const defaultMetricSelectionLimit = 3;
const defaultMetricPrefixes = [
  'train/',
  'val/',
  'valid/',
  'eval/',
  'test/',
];
const deprioritizedMetricPrefixes = [
  'system/',
  'slowest_rank/',
  'straggler/',
];
const headlineMetricTokens = [
  'loss',
  'accuracy',
  'acc',
  'error',
  'precision',
  'recall',
  'f1',
  'auc',
  'iou',
  'bleu',
  'perplexity',
  'reward',
];
const supportingMetricTokens = ['grad_norm', 'norm'];
const deprioritizedMetricTokens = [
  'epoch',
  'step',
  'learning_rate',
  'lr',
  'runtime',
  'time',
  'tokens',
  'batch',
  'pixel_elements',
  'memory',
  'cpu',
  'gpu',
  'rank',
];

const defaultSystemSelectionLimit = 3;
const systemPreferredTokens = [
  'gpu',
  'cpu',
  'memory',
  'util',
  'temperature',
  'temp',
  'power',
  'disk',
  'network',
];
const systemDeprioritizedTokens = [
  'error',
  'errors',
  'pid',
  'process',
  'correctedmemoryerrors',
  'uncorrectedmemoryerrors',
];

List<String> defaultMetricKeys(
  List<String> availableKeys,
  Map<String, dynamic> historyKeyMap,
) {
  final rankedKeys = [...availableKeys]..sort((a, b) {
    final scoreComparison = metricPriorityScore(
      b,
      historyKeyMap,
    ).compareTo(metricPriorityScore(a, historyKeyMap));
    if (scoreComparison != 0) {
      return scoreComparison;
    }
    return a.compareTo(b);
  });

  return rankedKeys.take(defaultMetricSelectionLimit).toList();
}

int metricPriorityScore(String key, Map<String, dynamic> historyKeyMap) {
  final lowerKey = key.toLowerCase();
  var score = 0;

  if (defaultMetricPrefixes.any(lowerKey.startsWith)) {
    score += 500;
  }

  if (deprioritizedMetricPrefixes.any(lowerKey.startsWith)) {
    score -= 350;
  }

  if (headlineMetricTokens.any(lowerKey.contains)) {
    score += 350;
  } else if (supportingMetricTokens.any(lowerKey.contains)) {
    score += 180;
  }

  if (deprioritizedMetricTokens.any(lowerKey.contains)) {
    score -= 275;
  }

  score += historyPointCountForKey(key, historyKeyMap) ~/ 200;
  return score;
}

int historyPointCountForKey(String key, Map<String, dynamic> historyKeyMap) {
  final entry = historyKeyMap[key];
  if (entry is! Map) return 0;

  final typeCounts = entry['typeCounts'];
  if (typeCounts is! List) return 0;

  var count = 0;
  for (final typeCount in typeCounts) {
    if (typeCount is! Map) continue;
    if (typeCount['type'] != 'number') continue;
    final rawCount = typeCount['count'];
    if (rawCount is num) {
      count += rawCount.toInt();
    }
  }
  return count;
}

List<String> defaultSystemKeys(List<String> availableKeys) {
  final rankedKeys = [...availableKeys]..sort((a, b) {
    final scoreComparison =
        systemMetricPriorityScore(b).compareTo(systemMetricPriorityScore(a));
    if (scoreComparison != 0) {
      return scoreComparison;
    }
    return a.compareTo(b);
  });

  return rankedKeys.take(defaultSystemSelectionLimit).toList();
}

int systemMetricPriorityScore(String key) {
  final lowerKey = key.toLowerCase();
  var score = 0;

  for (var index = 0; index < systemPreferredTokens.length; index++) {
    if (lowerKey.contains(systemPreferredTokens[index])) {
      score += math.max(8, 32 - index * 3);
    }
  }

  if (lowerKey.contains('system/')) {
    score += 10;
  }

  if (lowerKey.contains('util') || lowerKey.contains('usage')) {
    score += 16;
  }

  if (lowerKey.contains('temp') || lowerKey.contains('temperature')) {
    score += 14;
  }

  if (systemDeprioritizedTokens.any(lowerKey.contains)) {
    score -= 40;
  }

  return score;
}

String selectionSummary(Iterable<String> selectedKeys) {
  final selected = selectedKeys.toList(growable: false);
  if (selected.isEmpty) {
    return 'No metrics selected';
  }
  if (selected.length == 1) {
    return selected.first;
  }
  return '${selected.first}, +${selected.length - 1} more';
}

List<MetricSeries> selectedSeriesWithFallback(
  List<MetricSeries> series,
  Iterable<String> selectedKeys,
) {
  final seriesByKey = {for (final item in series) item.key: item};
  return selectedKeys
      .map(
        (key) =>
            seriesByKey[key] ?? MetricSeries(key: key, points: const <MetricPoint>[]),
      )
      .toList(growable: false);
}

List<MetricSeries> systemSeriesFromRows(
  Iterable<Map<String, Object?>> rows,
  Iterable<String> selectedKeys,
) {
  return selectedKeys.map((key) {
    final points = <MetricPoint>[];
    for (final row in rows) {
      final metrics = row['metrics'];
      if (metrics is! Map<String, double>) continue;
      final value = metrics[key];
      if (value == null) {
        continue;
      }
      final step = row['step'];
      final timestamp = row['timestamp'];
      if (step is! num) continue;
      points.add(
        MetricPoint(
          step: step,
          value: value,
          timestamp: timestamp is DateTime ? timestamp : null,
        ),
      );
    }
    return MetricSeries(key: key, points: points);
  }).toList(growable: false);
}
