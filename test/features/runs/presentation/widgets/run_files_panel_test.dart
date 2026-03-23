import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/models/run_file.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';
import 'package:wandb_mobile/features/runs/presentation/widgets/run_files_panel.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

class FilesRunsRepository extends RunsRepository {
  FilesRunsRepository() : super(GraphqlClient(apiKey: 'test'));

  @override
  Future<PaginatedResult<RunFile>> getRunFiles({
    required String entity,
    required String project,
    required String runName,
    String? cursor,
    int limit = 50,
    List<String>? fileNames,
  }) async {
    if (cursor == null) {
      return const PaginatedResult(
        items: [
          RunFile(
            id: 'file-1',
            name: 'output.log',
            directUrl: 'https://example.com/output.log',
            sizeBytes: 128,
            mimetype: 'text/plain',
          ),
        ],
        endCursor: 'cursor-1',
        hasNextPage: true,
        totalCount: 2,
      );
    }

    return const PaginatedResult(
      items: [
        RunFile(
          id: 'file-2',
          name: 'media/table.table.json',
          directUrl: 'https://example.com/table.json',
          sizeBytes: 256,
          mimetype: 'application/json',
        ),
      ],
      endCursor: 'cursor-2',
      hasNextPage: false,
      totalCount: 2,
    );
  }
}

Widget _buildFilesPanel(FilesRunsRepository repository) {
  return ProviderScope(
    overrides: [runsRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 700,
          height: 600,
          child: RunFilesPanel(
            entity: 'nv-gear',
            project: 'n1d6_ttt_fm_assembly',
            runName: 'b2sl4gke',
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders files and loads additional pages', (tester) async {
    final repository = FilesRunsRepository();

    await tester.pumpWidget(_buildFilesPanel(repository));
    await tester.pumpAndSettle();

    expect(find.text('output.log'), findsOneWidget);
    expect(find.text('Load more files'), findsOneWidget);

    await tester.tap(find.text('Load more files'));
    await tester.pumpAndSettle();

    expect(find.text('media/table.table.json'), findsOneWidget);
    expect(find.text('Load more files'), findsNothing);
  });
}
