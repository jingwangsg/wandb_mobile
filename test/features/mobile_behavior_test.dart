import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
import 'package:wandb_mobile/core/providers/api_client_provider.dart';
import 'package:wandb_mobile/core/providers/mobile_preferences.dart';
import 'package:wandb_mobile/core/utils/downsampling.dart';
import 'package:wandb_mobile/features/auth/providers/auth_providers.dart';
import 'package:wandb_mobile/features/charts/models/image_frame.dart';
import 'package:wandb_mobile/features/charts/models/metric_chart_rule.dart';
import 'package:wandb_mobile/features/notifications/data/push_service.dart';
import 'package:wandb_mobile/features/runs/presentation/widgets/run_logs_view.dart';

import '../test_support/mobile_test_support.dart';

void main() {
  test(
    'real authentication path saves the verified user ID with the key',
    () async {
      final storage = MemorySecureStorage();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          graphqlClientFactoryProvider.overrideWithValue(
            ({required apiKey, required baseUrl}) => ViewerClient(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(authProvider);
      await Future<void>.delayed(Duration.zero);
      await container.read(authProvider.notifier).login(apiKey: 'fixture-key');
      expect(container.read(authProvider).status, AuthStatus.authenticated);
      expect(storage.userId, 'user-1');
      expect(storage.apiKey, 'fixture-key');
      await container.read(authProvider.notifier).logout();
      expect(storage.userId, isNull);
      expect(storage.apiKey, isNull);
    },
  );

  test(
    'a null viewer is an authentication failure, not an authenticated empty account',
    () async {
      final storage = MemorySecureStorage();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          graphqlClientFactoryProvider.overrideWithValue(
            ({required apiKey, required baseUrl}) => ViewerClient(viewer: null),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(authProvider);
      await Future<void>.delayed(Duration.zero);
      await container.read(authProvider.notifier).login(apiKey: 'invalid');
      expect(container.read(authProvider).status, AuthStatus.unauthenticated);
      expect(storage.apiKey, isNull);
    },
  );

  test(
    'stars, visibility, and plot options persist without crossing account boundaries',
    () async {
      final store = MemoryMobilePreferencesStore();
      final first = MobilePreferencesNotifier(store, 'account-a');
      addTearDown(first.dispose);
      await first.toggleMetric('team/project', 'train/loss');
      await first.toggleRun('team/project', 'run-1');
      await first.setRule(
        'train/loss',
        const MetricChartRule(logScale: true, smoothing: 0.7),
      );
      await first.setTheme(ThemeMode.light);
      final restored = MobilePreferencesNotifier(store, 'account-a');
      final other = MobilePreferencesNotifier(store, 'account-b');
      addTearDown(restored.dispose);
      addTearDown(other.dispose);
      expect(restored.state.starredMetrics, first.state.starredMetrics);
      expect(restored.state.hiddenRuns['team/project'], {'run-1'});
      expect(
        restored.state.ruleFor('other-project', 'train/loss').logScale,
        true,
      );
      expect(restored.state.theme, ThemeMode.light);
      expect(other.state.starredMetrics, isEmpty);
      expect(other.state.hiddenRuns, isEmpty);
      expect(
        MobilePreferences.fromJson(restored.state.toJson()).toJson(),
        restored.state.toJson(),
      );
    },
  );

  test(
    'notification taps are scoped to the signed-in account and escaped paths',
    () {
      final message = {
        'owner': 'a',
        'entity': 'team',
        'project': 'training job',
        'run': 'run-1',
      };
      expect(
        notificationRoute(message, 'a'),
        '/projects/team/training%20job/runs/run-1',
      );
      expect(notificationRoute(message, 'b'), isNull);
      expect(notificationRoute(message, null), isNull);
      expect(notificationRoute({...message, 'run': ''}, 'a'), isNull);
    },
  );

  test(
    'TWEMA preserves a constant signal and finite values across sparse steps',
    () {
      final points = [
        for (final step in [0, 1, 50, 2000]) MetricPoint(step: step, value: 3),
      ];
      final smoothed = timeWeightedSmoothing(points, 0.99);
      for (final point in smoothed) {
        expect(point.value, closeTo(3, 1e-12));
      }
      expect(smoothed.map((p) => p.step), [0, 1, 50, 2000]);
      expect(timeWeightedSmoothing(points, 0), same(points));
    },
  );

  test(
    'media metadata retains all images, captions, and sparse step positions',
    () {
      final frame =
          imageFrameFromRow({
            '_step': 800,
            'samples': {
              '_type': 'images/separated',
              'filenames': ['a.png', 'b.png'],
              'captions': ['first', 'second'],
            },
          }, 'samples')!;
      expect(frame.images.map((image) => image.path), ['a.png', 'b.png']);
      expect(frame.images.last.caption, 'second');
      final frames = [
        const ImageFrame(step: 0, images: []),
        frame,
        const ImageFrame(step: 2000, images: []),
      ];
      expect(nearestImageFrame(frames, 950), 1);
      expect(nearestImageFrame(frames, 3000), 2);
      expect(
        imageFrameFromRow({'_step': 1, 'samples': 0.5}, 'samples'),
        isNull,
      );
    },
  );

  test('ANSI colors retain visible text and reset before following output', () {
    final spans = ansiLogSpans(
      '\x1b[31merror\x1b[0m recovered',
      const ColorScheme.light(),
    );
    expect(spans.map((span) => span.text).join(), 'error recovered');
    expect(spans.first.style!.color, isNotNull);
    expect(spans.last.style!.color, isNull);
  });
}
