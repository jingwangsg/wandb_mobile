import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/paginated.dart';
import 'package:wandb_mobile/core/models/project.dart';
import 'package:wandb_mobile/core/theme/app_theme.dart';
import 'package:wandb_mobile/features/auth/providers/auth_providers.dart';
import 'package:wandb_mobile/features/projects/data/projects_repository.dart';
import 'package:wandb_mobile/features/projects/presentation/projects_screen.dart';
import 'package:wandb_mobile/features/projects/providers/projects_providers.dart';

class FakeProjectsRepository extends ProjectsRepository {
  FakeProjectsRepository(this._result) : super(GraphqlClient(apiKey: 'test'));

  final PaginatedResult<WandbProject> _result;

  @override
  Future<PaginatedResult<WandbProject>> getProjects({
    required String entity,
    String? cursor,
    int perPage = 50,
  }) async {
    return _result;
  }
}

final _project = WandbProject(
  id: 'project-1',
  name: 'demo-project',
  entityName: 'nv-gear',
  description:
      'A long project description that should occupy two lines in the card without causing any layout overflow in grid mode.',
  createdAt: DateTime.utc(2024, 1, 1),
  runCount: 12,
);

Widget _buildProjectsScreen(FakeProjectsRepository repository) {
  return ProviderScope(
    overrides: [
      projectsRepositoryProvider.overrideWithValue(repository),
      currentEntityProvider.overrideWith((ref) => 'nv-gear'),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const ProjectsScreen(),
    ),
  );
}

Future<void> _pumpProjectsScreen(
  WidgetTester tester, {
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    _buildProjectsScreen(
      FakeProjectsRepository(
        PaginatedResult<WandbProject>(items: [_project], hasNextPage: false),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders project cards in grid mode without overflow', (
    tester,
  ) async {
    await _pumpProjectsScreen(tester, size: const Size(700, 800));

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('demo-project'), findsOneWidget);
    expect(find.text('12 runs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders project cards in list mode without overflow', (
    tester,
  ) async {
    await _pumpProjectsScreen(tester, size: const Size(390, 800));

    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('demo-project'), findsOneWidget);
    expect(find.text('12 runs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
