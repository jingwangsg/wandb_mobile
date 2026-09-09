import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/app.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/providers/api_client_provider.dart';
import 'package:wandb_mobile/core/providers/mobile_preferences.dart';
import 'package:wandb_mobile/core/theme/app_theme.dart';
import 'package:wandb_mobile/features/auth/presentation/login_screen.dart';
import 'package:wandb_mobile/features/charts/models/image_frame.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/image_metric_panel.dart';
import 'package:wandb_mobile/features/charts/providers/image_history_provider.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/presentation/runs_list_screen.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

import 'test_support/app_fixture.dart';
import 'test_support/mobile_test_support.dart';

class _ImageHistoryRepository extends RunsRepository {
  _ImageHistoryRepository(super.client, this.images);
  final List<LoggedImage> images;

  @override
  Future<List<Map<String, dynamic>>> getHistoryPage({
    required String entity,
    required String project,
    required String runName,
    required int minStep,
    required int maxStep,
    int pageSize = 500,
    List<String>? keys,
  }) async {
    if (entity != 'wandb' ||
        project != 'test-project' ||
        runName != 'run-1' ||
        minStep != 0 ||
        maxStep != 2 ||
        keys?.length != 1 ||
        keys!.single != 'samples') {
      throw StateError('Unexpected image fixture request');
    }
    return [
      {
        '_step': 1,
        'samples': {
          '_type': 'images/separated',
          'filenames': images.map((image) => image.path).toList(),
          'captions': images.map((image) => image.caption).toList(),
        },
      },
    ];
  }
}

void main() {
  testWidgets(
    'run search restores its query and chip deletion cancels pending input',
    (tester) async {
      const project = ProjectRef(entity: 'wandb', project: 'test-project');
      final container = ProviderContainer(
        overrides: [
          ...mobileTestOverrides(),
          runsRepositoryProvider.overrideWithValue(
            RunsRepository(AppFixtureClient()),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(runFiltersProvider(project).notifier)
          .setSearchQuery('retained');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const RunsListScreen(
              entity: 'wandb',
              project: 'test-project',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'Search runs',
      );
      final input = find.descendant(
        of: search,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(input).controller.text, 'retained');
      expect(find.text('Search: retained'), findsOneWidget);

      await tester.enterText(search, 'new query');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Search: new query'), findsOneWidget);
      final chip = find.widgetWithText(InputChip, 'Search: new query');
      await tester.tap(
        find.descendant(of: chip, matching: find.byType(Icon)).last,
      );
      await tester.pumpAndSettle();
      expect(container.read(runFiltersProvider(project)).searchQuery, isNull);
      expect(tester.widget<EditableText>(input).controller.text, isEmpty);

      await tester.enterText(search, 'settled');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.enterText(search, 'pending');
      await tester.pump(const Duration(milliseconds: 50));
      final pendingChip = find.widgetWithText(InputChip, 'Search: settled');
      await tester.tap(
        find.descendant(of: pendingChip, matching: find.byType(Icon)).last,
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(container.read(runFiltersProvider(project)).searchQuery, isNull);
      expect(tester.widget<EditableText>(input).controller.text, isEmpty);
      expect(find.byType(InputChip), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'dark login sends light Android status icons and restores them on return',
    (tester) async {
      final styles = <Map<dynamic, dynamic>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            styles.add(call.arguments as Map<dynamic, dynamic>);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
      await tester.idle();
      styles.clear();

      await tester.pumpWidget(
        ProviderScope(
          overrides: mobileTestOverrides(),
          child: MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        styles,
        isNotEmpty,
        reason: 'The fixed dark login must override the light app theme.',
      );
      expect(styles.last['statusBarIconBrightness'], 'Brightness.light');

      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(styles.last['statusBarIconBrightness'], 'Brightness.dark');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(styles.last['statusBarIconBrightness'], 'Brightness.light');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'selected dark navigation text contrasts with its rendered background',
    (tester) async {
      final storage =
          MemorySecureStorage()
            ..apiKey = 'fixture-key'
            ..entity = 'wandb';
      final client = AppFixtureClient();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          mobilePreferencesStoreProvider.overrideWithValue(
            MemoryMobilePreferencesStore(),
          ),
          graphqlClientFactoryProvider.overrideWithValue(
            ({required apiKey, required baseUrl}) => client,
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const WandbApp(),
        ),
      );
      await tester.pumpAndSettle();
      await container
          .read(mobilePreferencesProvider.notifier)
          .setTheme(ThemeMode.dark);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();

      final label = find.text('Profile').last;
      final text = tester.widget<Text>(label);
      final context = tester.element(label);
      var background = Theme.of(context).scaffoldBackgroundColor;
      final decorations = tester.widgetList<DecoratedBox>(
        find.ancestor(of: label, matching: find.byType(DecoratedBox)),
      );
      for (final decoration in decorations.toList().reversed) {
        final box = decoration.decoration;
        if (box is BoxDecoration && box.color != null) {
          background = Color.alphaBlend(box.color!, background);
        }
      }
      final foreground = Color.alphaBlend(text.style!.color!, background);
      final lighter = math.max(
        foreground.computeLuminance(),
        background.computeLuminance(),
      );
      final darker = math.min(
        foreground.computeLuminance(),
        background.computeLuminance(),
      );
      expect(
        (lighter + 0.05) / (darker + 0.05),
        greaterThanOrEqualTo(4.5),
        reason:
            'Selected labels are small text and must stay readable in dark mode.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(360, 800),
    const Size(393, 852),
    const Size(800, 393),
  ]) {
    testWidgets(
      'four logged images and captions fit the panel at ${size.width}x${size.height}',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const run = RunRef(
          entity: 'wandb',
          project: 'test-project',
          runName: 'run-1',
        );
        const metric = 'samples';
        final images = [
          for (var index = 0; index < 4; index++)
            LoggedImage(path: 'sample-$index.png', caption: 'Caption $index'),
        ];
        const framesRequest = (run: run, metric: metric);
        final historyClient = AppFixtureClient();
        addTearDown(historyClient.dispose);
        final urlsRequest = (
          run: run,
          paths: jsonEncode(images.map((image) => image.path).toList()),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...mobileTestOverrides(),
              imageHistoryProvider(framesRequest).overrideWith(
                (ref) => ImageHistoryLoader(
                  _ImageHistoryRepository(historyClient, images),
                  run,
                  metric,
                ),
              ),
              imageUrlsProvider(urlsRequest).overrideWith(
                (ref) async => {
                  for (final image in images)
                    image.path: 'https://images.invalid/${image.path}',
                },
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: ImageMetricPanel(
                    run: run,
                    metric: metric,
                    lastStep: 1,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final viewport = tester.getRect(find.byType(PageView));
        final tiles = find.byType(RunImage);
        expect(tiles, findsNWidgets(4));
        for (var index = 0; index < 4; index++) {
          final tile = tester.getRect(tiles.at(index));
          final caption = tester.getRect(find.text('Caption $index'));
          expect(tile.left, greaterThanOrEqualTo(viewport.left));
          expect(tile.right, lessThanOrEqualTo(viewport.right));
          expect(tile.top, greaterThanOrEqualTo(viewport.top));
          expect(
            tile.bottom,
            lessThanOrEqualTo(viewport.bottom),
            reason: 'Image $index must not be clipped.',
          );
          expect(
            caption.bottom,
            lessThanOrEqualTo(viewport.bottom),
            reason: 'Caption $index must be readable.',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
