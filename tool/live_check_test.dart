import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/providers/api_client_provider.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/core/providers/mobile_preferences.dart';
import 'package:wandb_mobile/features/charts/providers/panel_providers.dart';
import 'package:wandb_mobile/features/auth/providers/auth_providers.dart';
import 'package:wandb_mobile/features/projects/providers/projects_providers.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

import '../test/test_support/mobile_test_support.dart';

class LiveHttpOverrides extends HttpOverrides {}

void main() {
  testWidgets('read-only W&B authentication and repository integration', (
    tester,
  ) async {
    await tester.runAsync(
      () => HttpOverrides.runWithHttpOverrides(() async {
        final credentials = await Process.run('python3', [
          '-c',
          'import netrc,pathlib; a=netrc.netrc(str(pathlib.Path.home()/".netrc")).authenticators("api.wandb.ai"); assert a; print(a[2].strip(),end="")',
        ]);
        if (credentials.exitCode != 0)
          throw StateError('Cannot read W&B credentials from .netrc');
        final storage =
            MemorySecureStorage()..apiKey = credentials.stdout as String;
        final container = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            mobilePreferencesStoreProvider.overrideWithValue(
              MemoryMobilePreferencesStore(),
            ),
          ],
        );
        try {
          final ready = Completer<void>();
          final subscription = container.listen(authStatusProvider, (
            _,
            status,
          ) {
            if (status != AuthStatus.loading && !ready.isCompleted)
              ready.complete();
          }, fireImmediately: true);
          await ready.future.timeout(const Duration(seconds: 45));
          subscription.close();
          expect(container.read(authProvider).status, AuthStatus.authenticated);
          final runs = container.read(runsRepositoryProvider);
          final recent = await runs.getRecentRuns();
          expect(recent.items, isNotEmpty);
          const entity = 'nv-gear';
          const project = 'gr00t2_pretrain';
          final projects = await container
              .read(projectsRepositoryProvider)
              .getProjects(entity: entity);
          expect(projects.items, isNotEmpty);
          final run = await runs.getRun(
            entity: entity,
            project: project,
            runName: 'rz2hg2jr',
          );
          final keys =
              (run.historyKeys?['keys'] as Map? ?? {}).keys.cast<String>();
          const metric = 'train/loss';
          final history = await container.read(
            panelSeriesProvider((
              project: const ProjectRef(entity: entity, project: project),
              runName: run.name,
              metric: metric,
            )).future,
          );
          final logs = await runs.getLogs(
            entity: entity,
            project: project,
            runName: run.name,
            limit: 100,
          );
          final system = await runs.getSystemMetrics(
            entity: entity,
            project: project,
            runName: run.name,
            samples: 20,
          );
          expect(history.single.points, isNotEmpty);
          final catalog = await container.read(
            projectMetricKeysProvider(
              const ProjectRef(entity: entity, project: project),
            ).future,
          );
          expect(
            catalog.any(
              (key) => key.startsWith('system/') || key.startsWith('system.'),
            ),
            false,
          );
          final systemSeries = await container.read(
            runSystemSeriesProvider(
              RunRef(entity: entity, project: project, runName: run.name),
            ).future,
          );
          final cpu = systemSeries.singleWhere(
            (series) => series.key == 'system/cpu',
          );
          expect(cpu.points, isNotEmpty);
          final comparisonRuns = {
            run.name,
            recent.items
                .firstWhere(
                  (other) =>
                      other.entityName == entity &&
                      other.projectName == project &&
                      other.name != run.name,
                )
                .name,
          };
          String? cursor;
          do {
            final page = await runs.getRuns(
              entity: entity,
              project: project,
              cursor: cursor,
              perPage: 100,
            );
            for (final candidate in page.items) {
              if (!comparisonRuns.contains(candidate.name)) {
                await container
                    .read(mobilePreferencesProvider.notifier)
                    .toggleRun('$entity/$project', candidate.name);
              }
            }
            if (!page.hasNextPage) break;
            if (page.endCursor == null || page.endCursor == cursor)
              throw StateError('Run comparison pagination did not advance');
            cursor = page.endCursor;
          } while (true);
          final comparisonProvider = panelSeriesProvider((
            project: const ProjectRef(entity: entity, project: project),
            runName: null,
            metric: metric,
          ));
          // Keep the same active subscription that the Panels widget owns.
          final comparisonSubscription = container.listen(
            comparisonProvider,
            (_, _) {},
          );
          final comparison = await container.read(comparisonProvider.future);
          comparisonSubscription.close();
          expect(comparison.length, 2);
          for (final name in comparisonRuns) {
            expect(
              comparison
                  .singleWhere((line) => line.key.endsWith('($name)'))
                  .points,
              isNotEmpty,
            );
          }
          final report = {
            'authenticated': true,
            'username': container.read(authProvider).user!.username,
            'project': '$entity/$project',
            'run': run.name,
            'state': run.state.name,
            'numProjectsInPage': projects.items.length,
            'numMetrics': keys.length,
            'metric': metric,
            'numChartPoints': history.single.points.length,
            'numSystemSeries': systemSeries.length,
            'numCpuPoints': cpu.points.length,
            'lossStepRange': [
              history.single.points.first.step,
              history.single.points.last.step,
            ],
            'comparisonRuns': comparisonRuns.toList(),
            'comparisonPointCounts':
                comparison.map((line) => line.points.length).toList(),
            'numLogLines': logs.lines.length,
            'hasOlderLogs': logs.hasPreviousPage,
            'numSystemRows': system.length,
            'checkedAt': DateTime.now().toUtc().toIso8601String(),
          };
          await Directory('build/review').create(recursive: true);
          await File(
            'build/review/live-api.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
          // No credentials, configuration values, log content, or signed URLs are included.
          // ignore: avoid_print
          print(jsonEncode(report));
        } finally {
          container.dispose();
        }
      }, LiveHttpOverrides()),
    );
  });
}
