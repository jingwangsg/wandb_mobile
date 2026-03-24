import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';

void main() {
  test('ProjectRef equality is value-based', () {
    expect(
      const ProjectRef(entity: 'entity', project: 'project'),
      const ProjectRef(entity: 'entity', project: 'project'),
    );
  });

  test('RunRef exposes matching ProjectRef', () {
    const runRef = RunRef(
      entity: 'entity',
      project: 'project',
      runName: 'run-1',
    );

    expect(runRef.projectRef, const ProjectRef(entity: 'entity', project: 'project'));
  });
}
