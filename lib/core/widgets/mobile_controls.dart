import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_providers.dart';
import 'wandb_icon.dart';

class EntityPickerButton extends ConsumerWidget {
  const EntityPickerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entity = ref.watch(currentEntityProvider);
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed:
            () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const EntityPickerSheet(),
            ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 125),
              child: Text(
                entity,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const WandbIcon('chevron_(down)', size: 16),
          ],
        ),
      ),
    );
  }
}

class EntityPickerSheet extends ConsumerStatefulWidget {
  const EntityPickerSheet({super.key});
  @override
  ConsumerState<EntityPickerSheet> createState() => _EntityPickerSheetState();
}

class _EntityPickerSheetState extends ConsumerState<EntityPickerSheet> {
  String _query = '';
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final entities =
        (auth.user?.allEntities ?? [])
            .toSet()
            .where((e) => e.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Text('Select team', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search teams',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: entities.length,
                itemBuilder: (context, index) {
                  final entity = entities[index];
                  return ListTile(
                    leading: WandbIcon(
                      entity == auth.user?.entity
                          ? 'user_profile_personal'
                          : 'organization_corporate',
                    ),
                    title: Text(entity),
                    subtitle:
                        entity == auth.user?.entity
                            ? const Text('Personal')
                            : null,
                    trailing:
                        entity == auth.entity
                            ? const WandbIcon('checkmark')
                            : null,
                    onTap:
                        _saving
                            ? null
                            : () async {
                              setState(() => _saving = true);
                              try {
                                await ref
                                    .read(authProvider.notifier)
                                    .selectEntity(entity);
                                if (context.mounted) Navigator.pop(context);
                              } catch (error) {
                                if (context.mounted) {
                                  setState(() => _saving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$error')),
                                  );
                                }
                              }
                            },
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

class StarFilter extends StatelessWidget {
  const StarFilter({
    super.key,
    required this.starredOnly,
    required this.onChanged,
  });
  final bool starredOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final starred in [false, true])
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(starred ? 'Starred' : 'All'),
            selected: starredOnly == starred,
            showCheckmark: false,
            selectedColor: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(context).colorScheme.surface,
            labelStyle: TextStyle(
              fontSize: 16,
              color:
                  starredOnly == starred
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
            ),
            shape: const StadiumBorder(),
            side: BorderSide(
              color:
                  starredOnly == starred
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.outlineVariant,
            ),
            onSelected: (_) => onChanged(starred),
          ),
        ),
    ],
  );
}

class MobileEmptyState extends StatelessWidget {
  const MobileEmptyState({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.icon = 'folder_project',
  });
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final String icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WandbIcon(
            icon,
            size: 42,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    ),
  );
}
