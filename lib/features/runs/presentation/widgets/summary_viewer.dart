import 'package:flutter/material.dart';

import '../../../../core/utils/format_utils.dart';

/// Table displaying summary metrics for a run.
class SummaryViewer extends StatelessWidget {
  const SummaryViewer({super.key, required this.metrics});
  final Map<String, dynamic> metrics;

  @override
  Widget build(BuildContext context) {
    final entries = metrics.entries
        .where((e) => !e.key.startsWith('_'))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Summary',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${entries.length} metrics',
                    style: const TextStyle(color: Colors.white38)),
              ],
            ),
            const SizedBox(height: 12),
            ...entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          e.key,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          formatMetricValue(e.value),
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'JetBrains Mono',
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
