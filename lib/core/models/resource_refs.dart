class ProjectRef {
  const ProjectRef({required this.entity, required this.project});

  final String entity;
  final String project;

  String get path => '$entity/$project';

  factory ProjectRef.fromPath(String path) {
    final parts = path.split('/');
    if (parts.length != 2 || parts.any((part) => part.isEmpty)) {
      throw ArgumentError.value(
        path,
        'path',
        'Expected project path in the form "entity/project".',
      );
    }
    return ProjectRef(entity: parts[0], project: parts[1]);
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectRef && other.entity == entity && other.project == project;

  @override
  int get hashCode => Object.hash(entity, project);
}

class RunRef {
  const RunRef({
    required this.entity,
    required this.project,
    required this.runName,
  });

  final String entity;
  final String project;
  final String runName;

  ProjectRef get projectRef => ProjectRef(entity: entity, project: project);

  @override
  bool operator ==(Object other) =>
      other is RunRef &&
      other.entity == entity &&
      other.project == project &&
      other.runName == runName;

  @override
  int get hashCode => Object.hash(entity, project, runName);
}
