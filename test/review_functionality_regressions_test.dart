import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/models/run_log.dart';
import 'package:wandb_mobile/features/aria/data/aria_repository.dart';
import 'package:wandb_mobile/features/aria/presentation/aria_screen.dart';
import 'package:wandb_mobile/features/charts/models/metric_chart_rule.dart';
import 'package:wandb_mobile/features/charts/presentation/widgets/line_plot_settings.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/presentation/widgets/run_logs_view.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

class _RestoredAriaRepository extends AriaRepository {
  _RestoredAriaRepository() : super(apiKey: 'fixture-key');

  final restored = const AriaTurn({
    'id': 'saved-turn',
    'thread_id': 'saved-thread',
    'state': 'completed',
    'wandb_entity': 'team',
    'wandb_project': 'saved-project',
    'user_prompt': 'Explain the previous experiment',
    'messages': [],
  });
  String? continuationParent;
  AriaTurn? continuation;

  @override
  Future<List<Map<String, dynamic>>> threads({int offset = 0}) async {
    if (offset != 0) throw StateError('Unexpected thread offset: $offset');
    return [
      {
        'id': 'saved-thread',
        'title': 'Saved experiment review',
        'wandb_entity': 'team',
        'wandb_project': 'saved-project',
        'prompt_preview': 'Explain the previous experiment',
      },
    ];
  }

  @override
  Future<List<AriaTurn>> turns(String threadId) async {
    if (threadId != 'saved-thread') {
      throw StateError('Unexpected thread: $threadId');
    }
    return [restored];
  }

  @override
  Future<AriaTurn> createTurn(
    String prompt, {
    ProjectRef? project,
    String? parentId,
    List<Map<String, dynamic>> references = const [],
  }) async {
    if (parentId != restored.id || references.isNotEmpty) {
      throw StateError('Unexpected continuation parent: $parentId');
    }
    continuationParent = parentId;
    return continuation = AriaTurn({
      ...restored.data,
      'id': 'follow-up-turn',
      'parent_turn_id': parentId,
      'user_prompt': prompt,
    });
  }

  @override
  Future<AriaTurn> getTurn(String id, {CancelToken? cancelToken}) async {
    if (id != continuation?.id) throw StateError('Unexpected turn: $id');
    return continuation!;
  }
}

class _ScriptedLogsRepository extends RunsRepository {
  _ScriptedLogsRepository(super.client, this.pages);

  final Map<String?, Future<RunLogPage>> pages;
  final requestedAfter = <String?>[];

  @override
  Future<RunLogPage> getLogs({
    required String entity,
    required String project,
    required String runName,
    String? before,
    String? after,
    int limit = 10000,
  }) {
    if (entity != 'team' ||
        project != 'project' ||
        runName != 'run' ||
        before != null ||
        !pages.containsKey(after)) {
      throw StateError(
        'Unexpected log request: $entity/$project/$runName before=$before after=$after',
      );
    }
    requestedAfter.add(after);
    return pages[after]!;
  }
}

Widget _logsHarness(
  _ScriptedLogsRepository repository,
  ValueNotifier<bool> active,
) => ProviderScope(
  overrides: [runsRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: active,
        builder:
            (_, value, _) => RunLogsView(
              run: const RunRef(
                entity: 'team',
                project: 'project',
                runName: 'run',
              ),
              active: value,
              visible: true,
            ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'restored ARIA chats show their own project and continue the saved thread',
    (tester) async {
      final repository = _RestoredAriaRepository();
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ariaRepositoryProvider.overrideWithValue(repository),
            ariaProjectContextProvider.overrideWith(
              (_) =>
                  const ProjectRef(entity: 'team', project: 'browsed-project'),
            ),
          ],
          child: const MaterialApp(home: AriaScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('team/browsed-project'), findsOneWidget);

      await tester.tap(find.byTooltip('Chats'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved experiment review'));
      await tester.pumpAndSettle();

      expect(find.text('team/saved-project'), findsOneWidget);
      expect(find.text('team/browsed-project'), findsNothing);
      expect(find.text('Explain the previous experiment'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Why did this run stop?');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(repository.continuationParent, 'saved-turn');
      expect(find.text('team/saved-project'), findsOneWidget);
      expect(find.text('Why did this run stop?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a visible run ending fetches and drains its final log pages, then stops polling',
    (tester) async {
      final client = GraphqlClient(apiKey: 'fixture-key');
      final active = ValueNotifier(true);
      addTearDown(client.dispose);
      addTearDown(active.dispose);
      final repository = _ScriptedLogsRepository(client, {
        null: Future.value(
          const RunLogPage(
            lines: [RunLogLine(cursor: 'c0', text: 'Training is running')],
            startCursor: 'c0',
            endCursor: 'c0',
          ),
        ),
        'c0': Future.value(
          const RunLogPage(
            lines: [RunLogLine(cursor: 'c1', text: 'Saving final checkpoint')],
            startCursor: 'c1',
            endCursor: 'c1',
            hasNextPage: true,
          ),
        ),
        'c1': Future.value(
          const RunLogPage(
            lines: [
              RunLogLine(
                cursor: 'c2',
                text: 'FINAL: checkpoint saved; run finished',
              ),
            ],
            startCursor: 'c2',
            endCursor: 'c2',
          ),
        ),
        'c2': Future.value(const RunLogPage(lines: [], endCursor: 'c2')),
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_logsHarness(repository, active));
      await tester.pumpAndSettle();
      expect(find.text('Training is running'), findsOneWidget);

      active.value = false;
      await tester.pumpAndSettle();

      expect(find.text('Saving final checkpoint'), findsOneWidget);
      expect(
        find.text('FINAL: checkpoint saved; run finished'),
        findsOneWidget,
      );
      expect(repository.requestedAfter, containsAllInOrder([null, 'c0', 'c1']));
      final completedRequests = repository.requestedAfter.length;
      await tester.pump(const Duration(seconds: 15));
      expect(repository.requestedAfter.length, completedRequests);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ending while a log poll is in flight still fetches output written after that poll',
    (tester) async {
      final client = GraphqlClient(apiKey: 'fixture-key');
      final active = ValueNotifier(true);
      final inFlightPoll = Completer<RunLogPage>();
      addTearDown(client.dispose);
      addTearDown(active.dispose);
      final repository = _ScriptedLogsRepository(client, {
        null: Future.value(
          const RunLogPage(
            lines: [RunLogLine(cursor: 'c0', text: 'Training is running')],
            startCursor: 'c0',
            endCursor: 'c0',
          ),
        ),
        'c0': inFlightPoll.future,
        'c1': Future.value(
          const RunLogPage(
            lines: [RunLogLine(cursor: 'c2', text: 'FINAL: worker crashed')],
            startCursor: 'c2',
            endCursor: 'c2',
          ),
        ),
        'c2': Future.value(const RunLogPage(lines: [], endCursor: 'c2')),
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_logsHarness(repository, active));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(repository.requestedAfter, [null, 'c0']);

      active.value = false;
      await tester.pump();
      inFlightPoll.complete(
        const RunLogPage(
          lines: [RunLogLine(cursor: 'c1', text: 'Last batch before crash')],
          startCursor: 'c1',
          endCursor: 'c1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FINAL: worker crashed'), findsOneWidget);
      expect(repository.requestedAfter, containsAllInOrder([null, 'c0', 'c1']));
      final completedRequests = repository.requestedAfter.length;
      await tester.pump(const Duration(seconds: 15));
      expect(repository.requestedAfter.length, completedRequests);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final (name, escape, foreground, background) in <
    (String, String, Color?, Color?)
  >[
    ('RGB foreground', '\x1b[38;2;250;80;40m', const Color(0xFFFA5028), null),
    ('indexed foreground', '\x1b[38;5;196m', const Color(0xFFFF0000), null),
    (
      'indexed gray foreground',
      '\x1b[38;5;244m',
      const Color(0xFF808080),
      null,
    ),
    ('RGB background', '\x1b[48;2;23;55;85m', null, const Color(0xFF173755)),
    ('indexed background', '\x1b[48;5;22m', null, const Color(0xFF005F00)),
    (
      'combined foreground and background',
      '\x1b[38;2;255;0;0;48;5;22m',
      const Color(0xFFFF0000),
      const Color(0xFF005F00),
    ),
  ]) {
    test('ANSI $name renders exact colors and resets following text', () {
      final spans = ansiLogSpans(
        '${escape}colored\x1b[0m plain',
        const ColorScheme.light(),
      );
      expect(spans.map((span) => span.text).join(), 'colored plain');
      expect(spans.first.style?.color, foreground);
      expect(spans.first.style?.backgroundColor, background);
      expect(spans.last.style?.color, isNull);
      expect(spans.last.style?.backgroundColor, isNull);
    });
  }

  testWidgets(
    'resetting a plot shows inherited smoothing and preserves it on the next edit',
    (tester) async {
      MetricChartRule? saved;
      var resets = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LinePlotSettings(
              rule: const MetricChartRule(smoothing: 0.8),
              resetRule: const MetricChartRule(smoothing: 0.6),
              scope: 'Applies to this line plot',
              onChanged: (rule) => saved = rule,
              onReset: () => resets++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Reset this line plot'));
      await tester.pumpAndSettle();

      expect(resets, 1);
      expect(find.text('0.60'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.6);
      await tester.tap(find.text('Log scale (Y)'));
      await tester.pumpAndSettle();
      expect(saved?.logScale, true);
      expect(saved?.smoothing, 0.6);
      expect(tester.takeException(), isNull);
    },
  );
}
