import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/run.dart';
import '../core/widgets/wandb_icon.dart';
import '../features/aria/presentation/aria_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/projects/presentation/projects_screen.dart';
import '../features/runs/presentation/recent_runs_screen.dart';
import '../features/runs/presentation/run_detail_screen.dart';
import '../features/runs/presentation/runs_list_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final status = ref.watch(authStatusProvider);
  final router = GoRouter(
    initialLocation: '/runs',
    redirect: (context, state) {
      if (status != AuthStatus.authenticated &&
          state.matchedLocation != '/login')
        return '/login';
      if (status == AuthStatus.authenticated &&
          state.matchedLocation == '/login')
        return '/runs';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/dashboard', redirect: (_, _) => '/runs'),
      GoRoute(path: '/settings', redirect: (_, _) => '/profile'),
      StatefulShellRoute.indexedStack(
        builder:
            (context, state, shell) => _AppShell(
              shell: shell,
              showNavigation:
                  state.uri.path.split('/').where((s) => s.isNotEmpty).length ==
                  1,
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/runs',
                builder: (_, _) => const RecentRunsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/projects',
                builder: (_, _) => const ProjectsScreen(),
                routes: [
                  GoRoute(
                    path: ':entity/:project',
                    builder:
                        (_, state) => RunsListScreen(
                          entity: state.pathParameters['entity']!,
                          project: state.pathParameters['project']!,
                        ),
                    routes: [
                      GoRoute(
                        path: 'runs/:runName',
                        builder:
                            (_, state) => RunDetailScreen(
                              entity: state.pathParameters['entity']!,
                              project: state.pathParameters['project']!,
                              runName: state.pathParameters['runName']!,
                              run: state.extra as WandbRun?,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/aria', builder: (_, _) => const AriaScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notifications',
                builder: (_, _) => const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _AppShell extends StatelessWidget {
  const _AppShell({required this.shell, required this.showNavigation});
  final StatefulNavigationShell shell;
  final bool showNavigation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedColor =
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF7ED2DE)
            : const Color(0xFF337D8E);
    return Scaffold(
      body: shell,
      bottomNavigationBar:
          !showNavigation
              ? null
              : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.96),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.7),
                      ),
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        for (final (index, destination)
                            in const [
                              ('Runs', 'triangle_(right)', 'play_(filled)'),
                              (
                                'Projects',
                                'folder_project',
                                'folder_project_(filled)',
                              ),
                              ('ARIA', 'lightboard', 'lightboard_(filled)'),
                              (
                                'Notifications',
                                'bell_notifications',
                                'bell_notifications_(filled)',
                              ),
                              (
                                'Profile',
                                'user_profile_personal',
                                'user_profile_personal_(filled)',
                              ),
                            ].indexed)
                          Expanded(
                            child: Semantics(
                              selected: shell.currentIndex == index,
                              button: true,
                              label: destination.$1,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(32),
                                onTap:
                                    () => shell.goBranch(
                                      index,
                                      initialLocation:
                                          shell.currentIndex == index,
                                    ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        shell.currentIndex == index
                                            ? colors.onSurface.withValues(
                                              alpha: 0.07,
                                            )
                                            : null,
                                    borderRadius: BorderRadius.circular(32),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      WandbIcon(
                                        shell.currentIndex == index
                                            ? destination.$3
                                            : destination.$2,
                                        size: 23,
                                        color:
                                            shell.currentIndex == index
                                                ? selectedColor
                                                : colors.onSurface,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        destination.$1,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight:
                                              shell.currentIndex == index
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                          color:
                                              shell.currentIndex == index
                                                  ? selectedColor
                                                  : colors.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}
