import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/format_utils.dart';
import 'value_presentation.dart';

/// Table displaying summary metrics for a run.
class SummaryViewer extends StatefulWidget {
  const SummaryViewer({super.key, required this.metrics});
  final Map<String, dynamic> metrics;

  @override
  State<SummaryViewer> createState() => _SummaryViewerState();
}

class _SummaryViewerState extends State<SummaryViewer> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  Future<void> _copyText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied value')),
    );
  }

  Future<void> _copyValue(dynamic value) async {
    final presentation = ValuePresentation.fromValue(value);
    await Clipboard.setData(ClipboardData(text: presentation.fullText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied value')),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = widget.metrics.entries
        .where((e) => !e.key.startsWith('_'))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final entries =
        _searchQuery.isEmpty
            ? allEntries
            : allEntries
                .where(
                  (e) =>
                      e.key.toLowerCase().contains(_searchQuery.toLowerCase()),
                )
                .toList();
    final countText =
        _searchQuery.isEmpty
            ? '${allEntries.length} metrics'
            : '${entries.length}/${allEntries.length} metrics';

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
                Text(countText,
                    style: const TextStyle(color: Colors.white38)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Filter metrics...',
                hintStyle: const TextStyle(fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 14),
                suffixIcon:
                    _searchQuery.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                        : null,
                isDense: true,
                constraints: const BoxConstraints(minHeight: 34),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 8),
            ...entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: InkWell(
                          onTap: () => _copyText(e.key),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              e.key,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: InkWell(
                          onTap: () => _copyValue(e.value),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
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
