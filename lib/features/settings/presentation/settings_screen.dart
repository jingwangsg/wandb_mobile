import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_configuration.dart';
import '../../../core/providers/mobile_preferences.dart';
import '../../../core/widgets/mobile_controls.dart';
import '../../../core/widgets/wandb_icon.dart';
import '../../auth/providers/auth_providers.dart';
import '../../notifications/data/push_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final preferences = ref.watch(mobilePreferencesProvider);
    final push = ref.watch(pushServiceProvider);
    final username = auth.user?.username ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    child: Text(
                      username.isEmpty ? '?' : username[0].toUpperCase(),
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.user?.name ?? username,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          auth.user?.email ?? username,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const WandbIcon('organization_corporate'),
              title: Text(auth.entity),
              subtitle: Text(
                auth.entity == auth.user?.entity ? 'Personal' : 'Team',
              ),
              trailing: const WandbIcon('chevron_(next)', size: 18),
              onTap:
                  () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const EntityPickerSheet(),
                  ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Automatic')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {preferences.theme},
            onSelectionChanged: (selection) async {
              try {
                await ref
                    .read(mobilePreferencesProvider.notifier)
                    .setTheme(selection.single);
              } catch (error) {
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Unable to save appearance: $error'),
                    ),
                  );
              }
            },
          ),
          const SizedBox(height: 24),
          Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile.adaptive(
              secondary: const WandbIcon('bell_notifications'),
              title: const Text('Push notifications'),
              subtitle: Text(
                !AppConfiguration.pushConfigured
                    ? 'Unavailable in this build'
                    : push.hasError
                    ? '${push.error}'
                    : 'Run failures and metric changes',
              ),
              value: push.valueOrNull ?? false,
              onChanged:
                  !AppConfiguration.pushConfigured || push.isLoading
                      ? null
                      : (enabled) async {
                        try {
                          final service = ref.read(
                            pushServiceProvider.notifier,
                          );
                          if (enabled) {
                            await service.enable();
                          } else {
                            await service.disable();
                          }
                        } catch (error) {
                          if (context.mounted)
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text('$error')));
                        }
                      },
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const WandbIcon('help_(alt)'),
                  title: const Text('Contact Support'),
                  trailing: const WandbIcon('chevron_(next)', size: 18),
                  onTap: () => launchUrl(Uri.parse('mailto:support@wandb.com')),
                ),
                const Divider(indent: 52),
                ListTile(
                  leading: const WandbIcon('info'),
                  title: const Text('Licenses'),
                  trailing: const WandbIcon('chevron_(next)', size: 18),
                  onTap:
                      () => showLicensePage(
                        context: context,
                        applicationName: 'W&B for Android',
                        applicationVersion: '2.0.0',
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder:
                    (dialog) => AlertDialog(
                      title: const Text('Sign out?'),
                      content: const Text(
                        'Your API key will be removed from this device.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
              );
              if (confirmed != true) return;
              try {
                await ref.read(pushServiceProvider.notifier).disable();
              } catch (_) {
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Notifications were disabled locally. The push service could not confirm removal.',
                      ),
                    ),
                  );
              } finally {
                await ref.read(authProvider.notifier).logout();
              }
            },
            child: const Text('Sign out'),
          ),
          const SizedBox(height: 16),
          Text(
            'v2.0.0 (2)',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
