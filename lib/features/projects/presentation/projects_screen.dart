import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/project.dart';
import '../../../core/models/paginated.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/mobile_controls.dart';
import '../../../core/widgets/wandb_icon.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/projects_providers.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});
  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  String _query = '';
  bool _starredOnly = false;
  Timer? _debounce;
  Timer? _poll;
  final _pendingStars = <String>{};
  final _stars = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          TickerMode.valuesOf(context).enabled &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh(retainPages: true);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool retainPages = false}) {
    final entity = ref.read(currentEntityProvider);
    if (_starredOnly) {
      return ref
          .read(starredProjectsProvider.notifier)
          .load(retainPages: retainPages);
    }
    if (_query.isEmpty) {
      return ref
          .read(projectsProvider(entity).notifier)
          .load(retainPages: retainPages);
    }
    return ref
        .read(projectSearchProvider((entity: entity, query: _query)).notifier)
        .load(retainPages: retainPages);
  }

  Future<void> _loadMore() {
    final entity = ref.read(currentEntityProvider);
    if (_starredOnly) {
      return ref.read(starredProjectsProvider.notifier).loadMore();
    }
    if (_query.isEmpty) {
      return ref.read(projectsProvider(entity).notifier).loadMore();
    }
    return ref
        .read(projectSearchProvider((entity: entity, query: _query)).notifier)
        .loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final entity = ref.watch(currentEntityProvider);
    final AsyncValue<PaginatedResult<WandbProject>> projects =
        _starredOnly
            ? ref.watch(starredProjectsProvider)
            : _query.isEmpty
            ? ref.watch(projectsProvider(entity))
            : ref.watch(projectSearchProvider((entity: entity, query: _query)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: const [EntityPickerButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search in recent projects',
                prefixIcon: Padding(
                  padding: EdgeInsets.all(12),
                  child: WandbIcon('search'),
                ),
              ),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() => _query = value.trim());
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StarFilter(
              starredOnly: _starredOnly,
              onChanged: (value) => setState(() => _starredOnly = value),
            ),
          ),
          if (projects.isRefreshing)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: projects.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (error, _) => MobileEmptyState(
                    title: 'Unable to load projects',
                    message: '$error',
                    onRetry: _refresh,
                    icon: 'warning',
                  ),
              data: (page) {
                final items =
                    page.items
                        .where(
                          (p) =>
                              !_starredOnly ||
                              (p.entityName == entity &&
                                  p.name.toLowerCase().contains(
                                    _query.toLowerCase(),
                                  ) &&
                                  (_stars[p.id] ?? p.starred)),
                        )
                        .toList();
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notice) {
                      if (notice.metrics.extentAfter < 200 &&
                          page.hasNextPage) {
                        _loadMore();
                      }
                      return false;
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      children: [
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 64),
                            child: MobileEmptyState(
                              title:
                                  _starredOnly
                                      ? 'No starred projects'
                                      : 'No projects found',
                              message:
                                  _starredOnly
                                      ? 'Star a project to find it here.'
                                      : 'Try a different search or select another team.',
                            ),
                          ),
                        for (final project in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap:
                                    () => context.push(
                                      '/projects/${Uri.encodeComponent(project.entityName)}/${Uri.encodeComponent(project.name)}',
                                    ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    6,
                                    16,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              project.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.titleMedium,
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              formatRelativeTime(
                                                project.lastActive ??
                                                    project.createdAt,
                                              ),
                                              style:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip:
                                            (_stars[project.id] ??
                                                    project.starred)
                                                ? 'Unstar project'
                                                : 'Star project',
                                        onPressed:
                                            _pendingStars.contains(project.id)
                                                ? null
                                                : () async {
                                                  final value =
                                                      !(_stars[project.id] ??
                                                          project.starred);
                                                  setState(
                                                    () => _pendingStars.add(
                                                      project.id,
                                                    ),
                                                  );
                                                  try {
                                                    await ref
                                                        .read(
                                                          projectsRepositoryProvider,
                                                        )
                                                        .setStarred(
                                                          project,
                                                          value,
                                                        );
                                                    if (mounted) {
                                                      setState(
                                                        () =>
                                                            _stars[project.id] =
                                                                value,
                                                      );
                                                      ref.invalidate(
                                                        starredProjectsProvider,
                                                      );
                                                    }
                                                  } catch (error) {
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Could not save star: $error',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  } finally {
                                                    if (mounted) {
                                                      setState(
                                                        () => _pendingStars
                                                            .remove(project.id),
                                                      );
                                                    }
                                                  }
                                                },
                                        icon: WandbIcon(
                                          (_stars[project.id] ??
                                                  project.starred)
                                              ? 'star_(filled)'
                                              : 'star',
                                          color:
                                              (_stars[project.id] ??
                                                      project.starred)
                                                  ? WandbColors.star
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (page.hasNextPage)
                          TextButton(
                            onPressed: _loadMore,
                            child: const Text('Load more'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
