class MobileQueries {
  MobileQueries._();

  static const runFields = '''
    id name displayName state config summaryMetrics systemMetrics tags group
    jobType sweepName createdAt heartbeatAt description notes historyLineCount
    historyKeys readOnly user { username } project { name entityName }
  ''';

  static const recentRuns =
      r'''
    query MobileRecentRuns($cursor: String, $pattern: String) {
      viewer { runs(first: 30, after: $cursor, order: "-created_at", pattern: $pattern) {
        edges { node { ''' +
      runFields +
      r''' } }
        pageInfo { endCursor hasNextPage }
      } }
    }
  ''';

  static const run =
      r'''
    query MobileRun($entity: String!, $project: String!, $run: String!) {
      project(entityName: $entity, name: $project) {
        run(name: $run) { ''' +
      runFields +
      r''' }
      }
    }
  ''';

  static const stopRun = r'''
    mutation MobileStopRun($id: ID!) {
      stopRun(input: {id: $id}) { success }
    }
  ''';

  static const searchProjects = r'''
    query MobileSearchProjects($entity: String!, $pattern: String, $cursor: String) {
      projects(entityName: $entity, pattern: $pattern, first: 50, after: $cursor, order: "-lastActive") {
        edges { node { id name entityName description createdAt lastActive starred runCount user { username } } }
        pageInfo { endCursor hasNextPage }
      }
    }
  ''';

  static const starProject = r'''
    mutation MobileStarProject($entity: String!, $project: String!) {
      starProject(input: {entityName: $entity, projectName: $project}) { project { id starred } }
    }
  ''';

  static const unstarProject = r'''
    mutation MobileUnstarProject($entity: String!, $project: String!) {
      unstarProject(input: {entityName: $entity, projectName: $project}) { project { id starred } }
    }
  ''';

  static const projectMetrics = r'''
    query MobileProjectMetrics($entity: String!, $project: String!) {
      project(entityName: $entity, name: $project) {
        runs { historyKeys }
      }
    }
  ''';

  static const logs = r'''
    query MobileRunLogs($entity: String!, $project: String!, $run: String!,
                        $before: String, $after: String, $first: Int, $last: Int) {
      project(entityName: $entity, name: $project) {
        run(name: $run) {
          logLines(before: $before, after: $after, first: $first, last: $last, useImprovedPagination: true) {
            edges { cursor node { id line number timestamp level } }
            pageInfo { startCursor endCursor hasPreviousPage hasNextPage }
          }
        }
      }
    }
  ''';
}
