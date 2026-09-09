import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/image_metric_panel.dart';
import 'package:wandb_mobile/features/charts/providers/image_history_provider.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

import 'test_support/mobile_test_support.dart';

class _HistoryRepository extends RunsRepository {
  _HistoryRepository(super.client, this.responses);

  final List<Future<List<Map<String, dynamic>>>> responses;
  final requestedRanges = <(int, int)>[];

  @override
  Future<List<Map<String, dynamic>>> getHistoryPage({
    required String entity,
    required String project,
    required String runName,
    required int minStep,
    required int maxStep,
    int pageSize = 500,
    List<String>? keys,
  }) {
    if (entity != 'team' ||
        project != 'project' ||
        runName != 'run' ||
        keys?.length != 1 ||
        keys!.single != 'samples' ||
        requestedRanges.length >= responses.length) {
      throw StateError(
        'Unexpected image history request: $entity/$project/$runName [$minStep,$maxStep) $keys',
      );
    }
    requestedRanges.add((minStep, maxStep));
    return responses[requestedRanges.length - 1];
  }
}

const _run = RunRef(entity: 'team', project: 'project', runName: 'run');

void main() {
  testWidgets(
    'a live panel keeps loaded images through target updates and retry',
    (tester) async {
      final client = GraphqlClient(apiKey: 'fixture-key');
      final lastStep = ValueNotifier(1500);
      final first = Completer<List<Map<String, dynamic>>>();
      final failedPage = Completer<List<Map<String, dynamic>>>();
      final repository = _HistoryRepository(client, [
        first.future,
        failedPage.future,
        Future.value([
          {
            '_step': 1005,
            'samples': {'_type': 'image-file', 'path': 'second.png'},
          },
        ]),
        Future.value([
          {
            '_step': 2400,
            'samples': {'_type': 'image-file', 'path': 'last.png'},
          },
        ]),
      ]);
      addTearDown(client.dispose);
      addTearDown(lastStep.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...mobileTestOverrides(),
            runsRepositoryProvider.overrideWithValue(repository),
            imageUrlsProvider.overrideWith(
              (ref, request) async => <String, String>{},
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<int>(
                valueListenable: lastStep,
                builder:
                    (_, value, _) => ImageMetricPanel(
                      run: _run,
                      metric: 'samples',
                      lastStep: value,
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 31));
      lastStep.value = 2500;
      await tester.pump();
      expect(repository.requestedRanges, [(0, 1000)]);

      first.complete([
        {
          '_step': 5,
          'samples': {'_type': 'image-file', 'path': 'first.png'},
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Step 5'), findsOneWidget);
      failedPage.completeError(StateError('Temporary history failure'));
      await tester.pumpAndSettle();
      expect(find.text('Step 5'), findsOneWidget);
      await tester.tap(find.text('Unable to load more images · Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Step 2400'), findsOneWidget);
      expect(repository.requestedRanges, [
        (0, 1000),
        (1000, 2000),
        (1000, 2000),
        (2000, 2501),
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'advancing the target during a scan preserves progress and publishes each completed page',
    () async {
      final client = GraphqlClient(apiKey: 'fixture-key');
      final first = Completer<List<Map<String, dynamic>>>();
      final second = Completer<List<Map<String, dynamic>>>();
      final third = Completer<List<Map<String, dynamic>>>();
      final repository = _HistoryRepository(client, [
        first.future,
        second.future,
        third.future,
      ]);
      final loader = ImageHistoryLoader(repository, _run, 'samples');
      addTearDown(client.dispose);
      addTearDown(loader.dispose);

      final initialScan = loader.loadThrough(1500);
      await Future<void>.delayed(Duration.zero);
      expect(repository.requestedRanges, [(0, 1000)]);
      final extendedScan = loader.loadThrough(2500);
      await Future<void>.delayed(Duration.zero);
      expect(repository.requestedRanges, [(0, 1000)]);

      first.complete([
        {
          '_step': 5,
          'samples': {'_type': 'image-file', 'path': 'media/first.png'},
        },
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(loader.state.valueOrNull?.map((frame) => frame.step), [5]);
      expect(repository.requestedRanges, [(0, 1000), (1000, 2000)]);

      second.complete([
        {
          '_step': 1005,
          'samples': {'_type': 'image-file', 'path': 'media/second.png'},
        },
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(loader.state.valueOrNull?.map((frame) => frame.step), [5, 1005]);
      expect(repository.requestedRanges, [
        (0, 1000),
        (1000, 2000),
        (2000, 2501),
      ]);

      third.complete([
        {
          '_step': 2400,
          'samples': {'_type': 'image-file', 'path': 'media/third.png'},
        },
      ]);
      await Future.wait([initialScan, extendedScan]);
      expect(loader.state.valueOrNull?.map((frame) => frame.step), [
        5,
        1005,
        2400,
      ]);
      expect(
        loader.state.valueOrNull?.last.images.single.path,
        'media/third.png',
      );
      expect(loader.state.hasError, false);
    },
  );

  test(
    'loading newer steps starts after the completed partial range without replaying old pages',
    () async {
      final client = GraphqlClient(apiKey: 'fixture-key');
      final repository = _HistoryRepository(client, [
        Future.value([
          {
            '_step': 10,
            'samples': {'_type': 'image-file', 'path': 'media/first.png'},
          },
        ]),
        Future.value([
          {
            '_step': 1499,
            'samples': {'_type': 'image-file', 'path': 'media/second.png'},
          },
        ]),
        Future.value([
          {
            '_step': 1800,
            'samples': {'_type': 'image-file', 'path': 'media/third.png'},
          },
        ]),
      ]);
      final loader = ImageHistoryLoader(repository, _run, 'samples');
      addTearDown(client.dispose);
      addTearDown(loader.dispose);

      await loader.loadThrough(1500);
      expect(loader.state.valueOrNull?.map((frame) => frame.step), [10, 1499]);
      await loader.loadThrough(2000);
      await loader.loadThrough(2000);

      expect(repository.requestedRanges, [
        (0, 1000),
        (1000, 1501),
        (1501, 2001),
      ]);
      expect(loader.state.valueOrNull?.map((frame) => frame.step), [
        10,
        1499,
        1800,
      ]);
      expect(loader.state.hasError, false);
    },
  );

  test(
    'retry resumes the failed range and retains images already published',
    () async {
      final client = GraphqlClient(apiKey: 'fixture-key');
      final failedPage = Completer<List<Map<String, dynamic>>>();
      final repository = _HistoryRepository(client, [
        Future.value([
          {
            '_step': 50,
            'samples': {'_type': 'image-file', 'path': 'media/first.png'},
          },
        ]),
        failedPage.future,
        Future.value([
          {
            '_step': 1100,
            'samples': {'_type': 'image-file', 'path': 'media/recovered.png'},
          },
        ]),
      ]);
      final loader = ImageHistoryLoader(repository, _run, 'samples');
      addTearDown(client.dispose);
      addTearDown(loader.dispose);

      final initialScan = loader.loadThrough(1999);
      await Future<void>.delayed(Duration.zero);
      expect(repository.requestedRanges, [(0, 1000), (1000, 2000)]);
      expect(
        loader.state.valueOrNull?.single.images.single.path,
        'media/first.png',
      );
      failedPage.completeError(StateError('Temporary history failure'));
      await initialScan;

      expect(loader.state.hasError, true);
      expect(loader.state.valueOrNull?.map((frame) => frame.step), [50]);
      await loader.loadThrough(1999);

      expect(repository.requestedRanges, [
        (0, 1000),
        (1000, 2000),
        (1000, 2000),
      ]);
      expect(loader.state.valueOrNull?.map((frame) => frame.step), [50, 1100]);
      expect(loader.state.hasError, false);
    },
  );
}
