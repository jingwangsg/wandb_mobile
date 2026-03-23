import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../auth/providers/auth_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final entity = auth.entity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: WandbColors.yellow,
              child: Text(
                (auth.user?.username ?? '?')[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 600;
          final pad = wide ? 24.0 : 16.0;

          return ListView(
            padding: EdgeInsets.all(pad),
            children: [
              // Welcome card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, ${auth.user?.name ?? auth.user?.username ?? 'User'}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Entity: $entity',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Quick actions — adaptive grid
              const Text('Quick Actions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: wide ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: wide ? 1.8 : 1.5,
                children: [
                  _ActionCard(
                    icon: Icons.folder_open,
                    label: 'Projects',
                    onTap: () => _switchToTab(context, 1),
                  ),
                  _ActionCard(
                    icon: Icons.play_circle_outline,
                    label: 'Active Runs',
                    onTap: () => _switchToTab(context, 1),
                  ),
                  if (wide) ...[
                    _ActionCard(
                      icon: Icons.show_chart,
                      label: 'Charts',
                      onTap: () => _switchToTab(context, 1),
                    ),
                    _ActionCard(
                      icon: Icons.settings,
                      label: 'Settings',
                      onTap: () => context.go('/settings'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // Tips
              const Text('Getting Started',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Navigate to Projects to browse your experiments',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        wide
                            ? 'Click a run to view details in the side panel\n'
                              'Overview and Metrics are shown side-by-side'
                            : 'Tap a run to view metrics, config, and charts\n'
                              'Use pinch-to-zoom for chart interaction\n'
                              'Pull down to refresh any list',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _switchToTab(BuildContext context, int index) {
    // Use StatefulShellRoute to switch tabs
    if (index == 1) context.go('/projects');
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 32, color: WandbColors.yellow),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
