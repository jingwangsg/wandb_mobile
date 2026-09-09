import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/mobile_controls.dart';
import '../../../core/widgets/wandb_icon.dart';
import '../data/notifications_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(notificationRulesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Manage notifications')),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, _) => MobileEmptyState(
              title: 'Unable to load notifications',
              message: '$error',
              icon: 'bell_notifications',
              onRetry: () => ref.invalidate(notificationRulesProvider),
            ),
        data:
            (items) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(notificationRulesProvider);
                await ref.read(notificationRulesProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 64),
                      child: MobileEmptyState(
                        title: 'No notifications yet',
                        message:
                            'Notifications from your projects will appear here.',
                        icon: 'bell_notifications',
                      ),
                    ),
                  for (final metric in [false, true]) ...[
                    Text(
                      metric
                          ? 'Metric change notifications'
                          : 'Run failure notifications',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metric
                          ? 'Notifications created from project metrics'
                          : 'Projects you’ll be notified about when a run fails',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    for (final item in items.where(
                      (rule) => (rule.metric != null) == metric,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Dismissible(
                          key: ValueKey(item.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Theme.of(context).colorScheme.error,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const WandbIcon(
                              'delete',
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (_) async {
                            try {
                              await ref
                                  .read(notificationsRepositoryProvider)
                                  .delete(item.id);
                              ref.invalidate(notificationRulesProvider);
                              return false;
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not delete alert: $error',
                                    ),
                                  ),
                                );
                              }
                              return false;
                            }
                          },
                          child: Card(
                            child: ListTile(
                              leading: const WandbIcon('bell_notifications'),
                              title: Text(item.name),
                              subtitle: Text(
                                item.status == 'active'
                                    ? '${item.entity} · ${item.project}'
                                    : 'Setup incomplete · Swipe to remove and retry',
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                  if (items.isEmpty)
                    const Text(
                      'Create notifications from metric panels inside a project, or choose Run failed alert from the project menu.',
                    ),
                ],
              ),
            ),
      ),
    );
  }
}
