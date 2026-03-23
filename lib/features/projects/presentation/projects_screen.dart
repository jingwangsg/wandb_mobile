import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/project.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/wandb_mark_icon.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/projects_providers.dart';

const _kProjectGridItemExtent = 116.0;

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final entity = ref.watch(currentEntityProvider);
    final projectsAsync = ref.watch(projectsProvider(entity));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          // Entity selector
          TextButton(
            onPressed: () => _showEntitySelector(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entity, style: const TextStyle(color: Colors.white70)),
                const Icon(Icons.arrow_drop_down, color: Colors.white70),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search projects...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),

          // Project list
          Expanded(
            child: projectsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (e, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Error: $e'),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed:
                              () =>
                                  ref
                                      .read(projectsProvider(entity).notifier)
                                      .refresh(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
              data: (result) {
                final filtered =
                    _searchQuery.isEmpty
                        ? result.items
                        : result.items
                            .where(
                              (p) =>
                                  p.name.toLowerCase().contains(_searchQuery),
                            )
                            .toList();

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = adaptiveColumns(constraints.maxWidth);
                    final pad = adaptivePadding(constraints.maxWidth);

                    return RefreshIndicator(
                      onRefresh:
                          () =>
                              ref
                                  .read(projectsProvider(entity).notifier)
                                  .refresh(),
                      child:
                          cols == 1
                              ? ListView.builder(
                                padding: EdgeInsets.symmetric(horizontal: pad),
                                itemCount:
                                    filtered.length +
                                    (result.hasNextPage ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == filtered.length) {
                                    ref
                                        .read(projectsProvider(entity).notifier)
                                        .loadMore();
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  return _ProjectTile(project: filtered[index]);
                                },
                              )
                              : GridView.builder(
                                padding: EdgeInsets.all(pad),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: cols,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 8,
                                      mainAxisExtent: _kProjectGridItemExtent,
                                    ),
                                itemCount:
                                    filtered.length +
                                    (result.hasNextPage ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == filtered.length) {
                                    ref
                                        .read(projectsProvider(entity).notifier)
                                        .loadMore();
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }
                                  return _ProjectTile(
                                    project: filtered[index],
                                    inGrid: true,
                                  );
                                },
                              ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showEntitySelector(BuildContext context) {
    final auth = ref.read(authProvider);
    final entities = auth.user?.allEntities ?? [];

    showModalBottomSheet(
      context: context,
      builder:
          (context) => ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Select Entity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...entities.map(
                (e) => ListTile(
                  leading: Icon(
                    e == auth.user?.entity ? Icons.person : Icons.group,
                  ),
                  title: Text(e),
                  selected: e == auth.entity,
                  onTap: () {
                    ref.read(authProvider.notifier).selectEntity(e);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, this.inGrid = false});
  final WandbProject project;
  final bool inGrid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = project.description;
    final hasDescription = description != null && description.isNotEmpty;

    return Card(
      margin: EdgeInsets.only(bottom: inGrid ? 0 : 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          context.push('/projects/${project.entityName}/${project.name}');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: WandbMarkIcon(size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (hasDescription) ...[
                            const SizedBox(height: 4),
                            Text(
                              description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.72,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatRunCount(project.runCount),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall,
                  ),
                  if (project.createdAt != null)
                    Text(
                      formatRelativeTime(project.createdAt),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall,
                    ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatRunCount(int runCount) {
  if (runCount == 1) return '1 run';
  return '$runCount runs';
}
