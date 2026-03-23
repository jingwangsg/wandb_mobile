import 'package:flutter/material.dart';

import '../../../../core/utils/format_utils.dart';

/// Collapsible key-value tree for run config.
class ConfigViewer extends StatefulWidget {
  const ConfigViewer({super.key, required this.config});
  final Map<String, dynamic> config;

  @override
  State<ConfigViewer> createState() => _ConfigViewerState();
}

class _ConfigViewerState extends State<ConfigViewer> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('Config',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${widget.config.length} keys',
                      style: const TextStyle(color: Colors.white38)),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: widget.config.entries
                    .where((e) => !e.key.startsWith('_'))
                    .map((e) => _ConfigRow(
                          keyName: e.key,
                          value: e.value,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({required this.keyName, required this.value});
  final String keyName;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              keyName,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              formatMetricValue(value),
              style: const TextStyle(fontSize: 13, fontFamily: 'JetBrains Mono'),
            ),
          ),
        ],
      ),
    );
  }
}
