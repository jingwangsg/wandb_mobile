import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/resource_refs.dart';
import '../../../../core/models/run.dart';
import '../../../../core/providers/mobile_preferences.dart';
import '../../../../core/widgets/wandb_icon.dart';
import '../../models/run_grouping.dart';
import '../../providers/panel_providers.dart';

/// Bottom sheet choosing the keys project panels group runs by, mirroring
/// the web's Grouping tab: run fields and the listed runs' config entries.
class GroupingSheet extends ConsumerStatefulWidget {
  const GroupingSheet({super.key, required this.project});
  final ProjectRef project;

  @override
  ConsumerState<GroupingSheet> createState() => _GroupingSheetState();
}

class _GroupingSheetState extends ConsumerState<GroupingSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final runs = ref.watch(visibleRunsProvider(widget.project)).valueOrNull;
    final workspace =
        ref.watch(workspaceSettingsProvider(widget.project)).valueOrNull;
    final selected = ref.watch(
      mobilePreferencesProvider.select(
        (value) => groupingKeys(value.grouping, workspace, widget.project.path),
      ),
    );
    // An app choice (even "no grouping") hides the web's until reset.
    final overridden = ref.watch(
      mobilePreferencesProvider.select(
        (value) => value.grouping.containsKey(widget.project.path),
      ),
    );
    final configKeys =
        <String>{
            for (final run in runs?.candidates ?? const <WandbRun>[])
              for (final key in run.config.keys) 'config:$key',
          }.toList()
          ..sort();
    final query = _query.toLowerCase();
    final options =
        {
          for (final key in [...selected, ...runGroupingKeys, ...configKeys])
            if (key.toLowerCase().contains(query)) key,
        }.toList();
    final notifier = ref.read(mobilePreferencesProvider.notifier);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Group runs by',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (overridden)
                    TextButton(
                      onPressed:
                          () => notifier.resetGrouping(widget.project.path),
                      child: const Text('Reset'),
                    )
                  else if (selected.isNotEmpty)
                    TextButton(
                      onPressed:
                          () => notifier.setGrouping(
                            widget.project.path,
                            const [],
                          ),
                      child: const Text('Clear'),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const WandbIcon('close'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search keys',
                  prefixIcon: Padding(
                    padding: EdgeInsets.all(12),
                    child: WandbIcon('search'),
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final key = options[index];
                  final checked = selected.contains(key);
                  return CheckboxListTile(
                    title: Text(key.substring(key.indexOf(':') + 1)),
                    subtitle: Text(key.startsWith('run:') ? 'Run' : 'Config'),
                    value: checked,
                    onChanged:
                        (_) => notifier.setGrouping(widget.project.path, [
                          for (final other in selected)
                            if (other != key) other,
                          if (!checked) key,
                        ]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
