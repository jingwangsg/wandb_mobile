import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../auth/providers/auth_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Account section
          _SectionHeader('Account'),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: WandbColors.yellow,
              child: Text(
                (auth.user?.username ?? '?')[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(auth.user?.username ?? 'Unknown'),
            subtitle: Text(auth.user?.email ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Entity'),
            subtitle: Text(auth.entity),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showEntityPicker(context, ref),
          ),
          const Divider(),

          // Preferences
          _SectionHeader('Preferences'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Dark Mode'),
            subtitle: const Text('Currently always dark'),
            value: true,
            onChanged: null, // TODO: implement theme switching
          ),
          const Divider(),

          // Cache
          _SectionHeader('Data'),
          ListTile(
            leading: const Icon(Icons.cached),
            title: const Text('Clear Cache'),
            subtitle: const Text('Remove all cached data'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            },
          ),
          const Divider(),

          // About
          _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('W&B Mobile'),
            subtitle: Text('Version 1.0.0'),
          ),
          const Divider(),

          // Logout
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.tonal(
              onPressed: () => _confirmLogout(context, ref),
              style: FilledButton.styleFrom(
                foregroundColor: WandbColors.failed,
              ),
              child: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }

  void _showEntityPicker(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authProvider);
    final entities = auth.user?.allEntities ?? [];

    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: entities
            .map((e) => ListTile(
                  title: Text(e),
                  selected: e == auth.entity,
                  onTap: () {
                    ref.read(authProvider.notifier).selectEntity(e);
                    Navigator.pop(context);
                  },
                ))
            .toList(),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('This will clear your API key. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: WandbColors.yellow,
        ),
      ),
    );
  }
}
