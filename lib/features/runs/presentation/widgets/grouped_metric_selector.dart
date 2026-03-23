import 'dart:collection';

import 'package:flutter/material.dart';

Set<String> metricGroupPathsForKey(String key) {
  final segments = key.split('/');
  if (segments.length <= 1) return const {};

  final paths = <String>{};
  for (var i = 1; i < segments.length; i++) {
    paths.add(segments.take(i).join('/'));
  }
  return paths;
}

class GroupedMetricSelector extends StatelessWidget {
  const GroupedMetricSelector({
    super.key,
    required this.metricKeys,
    required this.selectedKeys,
    required this.expandedGroupPaths,
    required this.onToggleMetric,
    required this.onToggleGroup,
    this.compact = false,
    this.padding = EdgeInsets.zero,
  });

  final List<String> metricKeys;
  final Set<String> selectedKeys;
  final Set<String> expandedGroupPaths;
  final ValueChanged<String> onToggleMetric;
  final void Function(String path, bool expanded) onToggleGroup;
  final bool compact;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final nodes = _MetricTreeBuilder(metricKeys).build();
    return ListView(
      padding: padding,
      children: nodes.map((node) => _buildNode(context, node, 0)).toList(),
    );
  }

  Widget _buildNode(BuildContext context, _MetricTreeNode node, int depth) {
    if (node.metricKey != null) {
      return _MetricLeafTile(
        label: node.label,
        metricKey: node.metricKey!,
        selected: selectedKeys.contains(node.metricKey),
        compact: compact,
        depth: depth,
        onToggle: onToggleMetric,
      );
    }

    final path = node.path!;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('metric-group-$path'),
        title: Text(
          node.label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        tilePadding: EdgeInsets.only(
          left: 12.0 * depth + (compact ? 8 : 12),
          right: compact ? 8 : 12,
        ),
        childrenPadding: EdgeInsets.zero,
        maintainState: true,
        initiallyExpanded: expandedGroupPaths.contains(path),
        onExpansionChanged: (expanded) => onToggleGroup(path, expanded),
        children:
            node.children
                .map((child) => _buildNode(context, child, depth + 1))
                .toList(),
      ),
    );
  }
}

class _MetricLeafTile extends StatelessWidget {
  const _MetricLeafTile({
    required this.label,
    required this.metricKey,
    required this.selected,
    required this.compact,
    required this.depth,
    required this.onToggle,
  });

  final String label;
  final String metricKey;
  final bool selected;
  final bool compact;
  final int depth;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onToggle(metricKey),
      child: Padding(
        padding: EdgeInsets.only(
          left: 12.0 * depth + (compact ? 12 : 16),
          right: compact ? 8 : 12,
        ),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              visualDensity: compact ? VisualDensity.compact : null,
              onChanged: (_) => onToggle(metricKey),
            ),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTreeBuilder {
  _MetricTreeBuilder(List<String> metricKeys)
    : _metricKeys = [...metricKeys]..sort();

  final List<String> _metricKeys;

  List<_MetricTreeNode> build() {
    final root = _MutableMetricGroupNode.root();
    for (final key in _metricKeys) {
      final segments = key.split('/');
      if (segments.length == 1) {
        root.leafKeys[key] = _MetricTreeNode.leaf(
          label: segments.first,
          metricKey: key,
        );
        continue;
      }

      var current = root;
      final currentPath = <String>[];
      for (final segment in segments.take(segments.length - 1)) {
        currentPath.add(segment);
        final path = currentPath.join('/');
        current = current.groupChildren.putIfAbsent(
          segment,
          () => _MutableMetricGroupNode(segment, path),
        );
      }

      current.leafKeys[key] = _MetricTreeNode.leaf(
        label: segments.last,
        metricKey: key,
      );
    }

    return _sortedChildren(root);
  }

  List<_MetricTreeNode> _sortedChildren(_MutableMetricGroupNode group) {
    final children = <_MetricTreeNode>[
      ...group.groupChildren.values.map(
        (child) => _MetricTreeNode.group(
          label: child.label,
          path: child.path,
          children: _sortedChildren(child),
        ),
      ),
      ...group.leafKeys.values,
    ];

    children.sort((a, b) {
      if (a.metricKey == null && b.metricKey != null) return -1;
      if (a.metricKey != null && b.metricKey == null) return 1;
      return a.label.compareTo(b.label);
    });
    return List.unmodifiable(children);
  }
}

class _MutableMetricGroupNode {
  _MutableMetricGroupNode(this.label, this.path);

  _MutableMetricGroupNode.root() : label = '', path = '';

  final String label;
  final String path;
  final Map<String, _MutableMetricGroupNode> groupChildren =
      SplayTreeMap<String, _MutableMetricGroupNode>();
  final Map<String, _MetricTreeNode> leafKeys =
      SplayTreeMap<String, _MetricTreeNode>();
}

class _MetricTreeNode {
  const _MetricTreeNode._({
    required this.label,
    required this.path,
    required this.metricKey,
    required this.children,
  });

  const _MetricTreeNode.group({
    required String label,
    required String path,
    required List<_MetricTreeNode> children,
  }) : this._(label: label, path: path, metricKey: null, children: children);

  const _MetricTreeNode.leaf({required String label, required String metricKey})
    : this._(
        label: label,
        path: null,
        metricKey: metricKey,
        children: const [],
      );

  final String label;
  final String? path;
  final String? metricKey;
  final List<_MetricTreeNode> children;
}
