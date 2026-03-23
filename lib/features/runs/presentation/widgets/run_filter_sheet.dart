import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colors.dart';
import '../../providers/runs_providers.dart';

class RunFilterSheet extends ConsumerWidget {
  const RunFilterSheet({super.key, required this.projectPath});
  final String projectPath;

  static const _states = [
    'running',
    'finished',
    'failed',
    'crashed',
    'preempted',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(runFiltersProvider(projectPath));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Filter Runs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  ref.read(runFiltersProvider(projectPath).notifier).state =
                      const RunFilters();
                  Navigator.pop(context);
                },
                child: const Text('Clear All'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Status', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _states.map((state) {
              final isSelected = filters.state == state;
              final color = WandbColors.forRunState(state);
              return FilterChip(
                label: Text(state),
                selected: isSelected,
                selectedColor: color.withValues(alpha: 0.3),
                checkmarkColor: color,
                onSelected: (selected) {
                  ref.read(runFiltersProvider(projectPath).notifier).state =
                      selected
                          ? filters.copyWith(state: state)
                          : filters.copyWith(clearState: true);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Apply'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
