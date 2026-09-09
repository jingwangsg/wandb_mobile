import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/app.dart';
import 'package:wandb_mobile/core/providers/api_client_provider.dart';
import 'package:wandb_mobile/core/providers/mobile_preferences.dart';
import 'package:wandb_mobile/features/aria/data/aria_repository.dart';
import 'package:wandb_mobile/features/charts/presentation/panels_view.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/wandb_line_chart.dart';
import 'package:wandb_mobile/features/notifications/data/notifications_repository.dart';
import 'package:wandb_mobile/routing/app_router.dart';

import 'test_support/app_fixture.dart';
import 'test_support/mobile_test_support.dart';

Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final context = tester.element(find.byKey(const Key('capture')));
    for (final asset in manifest.listAssets().where(
      (asset) => asset.startsWith('assets/icons/'),
    )) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('capture')),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/review').create(recursive: true);
    await File(
      'build/review/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'Android flows: projects, stars, run tabs, ARIA, alerts and theme',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        for (final font in [
          ('SourceSans3', 'SourceSans3-VariableFont_wght.ttf'),
          ('Inconsolata', 'Inconsolata-VariableFont_wdth,wght.ttf'),
        ]) {
          await (FontLoader(font.$1)
            ..addFont(rootBundle.load('assets/fonts/${font.$2}'))).load();
        }
        await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      final client = AppFixtureClient();
      final aria = FixtureAriaRepository();
      final notifications = FixtureNotificationsRepository();
      final storage =
          MemorySecureStorage()
            ..apiKey = 'fixture-key'
            ..entity = 'wandb';
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          mobilePreferencesStoreProvider.overrideWithValue(
            MemoryMobilePreferencesStore(),
          ),
          graphqlClientFactoryProvider.overrideWithValue(
            ({required apiKey, required baseUrl}) => client,
          ),
          ariaRepositoryProvider.overrideWithValue(aria),
          notificationsRepositoryProvider.overrideWithValue(notifications),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RepaintBoundary(key: Key('capture'), child: WandbApp()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your runs'), findsOneWidget);
      expect(find.text('experiment-1'), findsOneWidget);
      await capture(tester, 'runs');

      await tester.tap(find.text('Projects').last);
      await tester.pumpAndSettle();
      expect(find.text('llama-sft-customer-support'), findsOneWidget);
      await capture(tester, 'projects');
      await tester.tap(find.byTooltip('Star project').first);
      await tester.pumpAndSettle();
      expect(client.starred, contains('llama-sft-customer-support'));
      await tester.tap(find.text('Starred'));
      await tester.pumpAndSettle();
      expect(find.text('scaling-benchmark-a100'), findsNothing);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('llama-sft-customer-support'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Panels'));
      await tester.pumpAndSettle();
      expect(find.text('train/loss'), findsOneWidget);
      final lossChart = tester.widget<WandbLineChart>(
        find.descendant(
          of: find.widgetWithText(MetricPanelCard, 'train/loss'),
          matching: find.byType(WandbLineChart),
        ),
      );
      expect(lossChart.series.map((line) => line.key), [
        'experiment-1 (run-1)',
        'experiment-2 (run-2)',
      ]);
      expect(
        lossChart.series[0].points.last.value,
        lessThan(lossChart.series[1].points.last.value),
      );
      await capture(tester, 'panels');
      await tester.tap(find.byTooltip('Open panel').first);
      await tester.pumpAndSettle();
      final comparison = tester.widget<WandbLineChart>(
        find.byType(WandbLineChart),
      );
      expect(comparison.series.length, 2);
      expect(comparison.showLegend, true);
      await capture(tester, 'compare-runs');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Runs').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hide run from panels').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show run in panels'), findsOneWidget);
      await tester.tap(find.text('Panels'));
      await tester.pumpAndSettle();
      final filteredChart = tester.widget<WandbLineChart>(
        find.descendant(
          of: find.widgetWithText(MetricPanelCard, 'train/loss'),
          matching: find.byType(WandbLineChart),
        ),
      );
      expect(filteredChart.series.map((line) => line.key), [
        'experiment-2 (run-2)',
      ]);
      await tester.tap(find.text('Runs').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show run in panels'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Panels'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WandbLineChart>(
              find.descendant(
                of: find.widgetWithText(MetricPanelCard, 'train/loss'),
                matching: find.byType(WandbLineChart),
              ),
            )
            .series
            .length,
        2,
      );
      await tester.tap(find.text('Runs').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('experiment-1'));
      await tester.pumpAndSettle();
      expect(find.text('Charts'), findsOneWidget);
      await capture(tester, 'charts');
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Run overview'), findsOneWidget);
      await capture(tester, 'overview');
      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();
      expect(find.text('step=0 loss=0.9000'), findsOneWidget);
      await capture(tester, 'logs');

      container.read(routerProvider).go('/aria');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'How are my active runs doing?',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Loss'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'Which one has the lower loss?',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(aria.parentIds, [null, 'turn-1']);
      expect(find.text('Which one has the lower loss?'), findsOneWidget);
      await capture(tester, 'aria');

      await tester.tap(find.text('Notifications').last);
      await tester.pumpAndSettle();
      expect(find.text('Run failed'), findsOneWidget);
      await capture(tester, 'notifications');
      await tester.drag(find.byType(Dismissible).first, const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(notifications.items, isEmpty);

      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(container.read(mobilePreferencesProvider).theme, ThemeMode.dark);
      await capture(tester, 'profile-dark');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
