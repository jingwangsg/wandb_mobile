import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

}
