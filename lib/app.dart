import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/providers/mobile_preferences.dart';
import 'routing/app_router.dart';
import 'features/notifications/data/push_service.dart';

class WandbApp extends ConsumerWidget {
  const WandbApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.watch(pushServiceProvider);
    ref.listen(pendingNotificationRouteProvider, (_, path) {
      if (path != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          router.go(path);
          ref.read(pendingNotificationRouteProvider.notifier).state = null;
        });
      }
    });

    return MaterialApp.router(
      title: 'W&B Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(
        mobilePreferencesProvider.select((value) => value.theme),
      ),
      routerConfig: router,
    );
  }
}
