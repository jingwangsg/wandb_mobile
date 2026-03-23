import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/models/project.dart';

void main() {
  test('parses runCount from GraphQL payload', () {
    final project = WandbProject.fromJson({
      'id': 'project-id',
      'name': 'demo-project',
      'entityName': 'demo-entity',
      'description': 'Example project',
      'createdAt': '2025-01-01T00:00:00Z',
      'runCount': 42,
      'isBenchmark': false,
      'user': {'username': 'wandb'},
    });

    expect(project.runCount, 42);
    expect(project.path, 'demo-entity/demo-project');
  });
}
