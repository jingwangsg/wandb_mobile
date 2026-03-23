import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format_utils.dart';
import '../../../core/utils/responsive.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/projects_providers.dart';

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
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Error: $e'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () =>
                          ref.read(projectsProvider(entity).notifier).refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (result) {
                final filtered = _searchQuery.isEmpty
                    ? result.items
                    : result.items
                        .where((p) =>
                            p.name.toLowerCase().contains(_searchQuery))
                        .toList();

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = adaptiveColumns(constraints.maxWidth);
                    final pad = adaptivePadding(constraints.maxWidth);

                    return RefreshIndicator(
                      onRefresh: () => ref
                          .read(projectsProvider(entity).notifier)
                          .refresh(),
                      child: cols == 1
                          ? ListView.builder(
                              padding: EdgeInsets.symmetric(horizontal: pad),
                              itemCount: filtered.length +
                                  (result.hasNextPage ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == filtered.length) {
                                  ref
                                      .read(
                                          projectsProvider(entity).notifier)
                                      .loadMore();
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                return _ProjectTile(
                                    project: filtered[index]);
                              },
                            )
                          : GridView.builder(
                              padding: EdgeInsets.all(pad),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 2.5,
                              ),
                              itemCount: filtered.length +
                                  (result.hasNextPage ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == filtered.length) {
                                  ref
                                      .read(
                                          projectsProvider(entity).notifier)
                                      .loadMore();
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                return _ProjectTile(
                                    project: filtered[index]);
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
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Select Entity',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...entities.map((e) => ListTile(
                leading: Icon(
                  e == auth.user?.entity ? Icons.person : Icons.group,
                ),
                title: Text(e),
                selected: e == auth.entity,
                onTap: () {
                  ref.read(authProvider.notifier).selectEntity(e);
                  Navigator.pop(context);
                },
              )),
        ],
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project});
  final dynamic project; // WandbProject

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          project.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: project.description != null && project.description!.isNotEmpty
            ? Text(
                project.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54),
              )
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Icon(Icons.chevron_right, color: Colors.white38),
            if (project.createdAt != null)
              Text(
                formatRelativeTime(project.createdAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        onTap: () {
          context.push('/projects/${project.entityName}/${project.name}');
        },
      ),
    );
  }
}
