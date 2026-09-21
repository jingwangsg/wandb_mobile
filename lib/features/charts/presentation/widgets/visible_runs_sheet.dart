import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/resource_refs.dart';
import '../../../../core/providers/mobile_preferences.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/widgets/wandb_icon.dart';
import '../../providers/panel_providers.dart';

/// Bottom sheet for project panels: how many runs to draw and an eye toggle
/// per listed run, mirroring the web's run selector.
class VisibleRunsSheet extends ConsumerWidget {
  const VisibleRunsSheet({super.key, required this.project});
  final ProjectRef project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(visibleRunsProvider(project));
    final data = runs.valueOrNull;
    final workspace = ref.watch(workspaceSettingsProvider(project)).valueOrNull;
    final overrides = ref.watch(
      mobilePreferencesProvider.select(
        (value) => value.runVisibility[project.path],
      ),
    );
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
                      'Visible runs',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Expanded(child: Text('Show up to')),
                  DropdownButton<int>(
                    value: data?.limit,
                    items: [
                      for (final value
                          in {
                              5,
                              10,
                              20,
                              50,
                              100,
                              if (data != null) data.limit,
                            }.toList()
                            ..sort())
                        DropdownMenuItem(
                          value: value,
                          child: Text('$value runs'),
                        ),
                    ],
                    onChanged:
                        data == null
                            ? null
                            : (value) {
                              if (value != null) {
                                notifier.setVisibleRunLimit(
                                  project.path,
                                  value,
                                );
                              }
                            },
                  ),
                ],
              ),
            ),
            if (runs.isLoading) const LinearProgressIndicator(minHeight: 2),
            const Divider(height: 1),
            Expanded(
              child:
                  data == null
                      ? const SizedBox.shrink()
                      : ListView.builder(
                        itemCount: data.candidates.length,
                        itemBuilder: (context, index) {
                          final run = data.candidates[index];
                          final eligible = isRunVisible(
                            overrides,
                            workspace,
                            run.name,
                          );
                          final drawn = data.visible.contains(run);
                          return ListTile(
                            leading: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: WandbColors.forRunState(run.state.name),
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(
                              run.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle:
                                eligible && !drawn
                                    ? const Text('Over the visible run limit')
                                    : null,
                            trailing: IconButton(
                              tooltip:
                                  eligible
                                      ? 'Hide run from panels'
                                      : 'Show run in panels',
                              onPressed:
                                  () => notifier.setRunVisible(
                                    project.path,
                                    run.name,
                                    !eligible,
                                  ),
                              icon: WandbIcon(
                                eligible ? 'visible' : 'not_visible',
                                size: 20,
                              ),
                            ),
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
