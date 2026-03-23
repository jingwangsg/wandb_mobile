/// All GraphQL query strings extracted from the wandb Python SDK.
/// Endpoint: https://api.wandb.ai/graphql
/// Auth: HTTP Basic Auth (username="api", password=apiKey)
class WandbQueries {
  WandbQueries._();

  // ─── Auth ──────────────────────────────────────────────
  static const getViewer = r'''
query GetViewer {
  viewer {
    id
    name
    username
    email
    admin
    entity
    teams {
      edges {
        node { name }
      }
    }
  }
}
''';

  // ─── Projects ──────────────────────────────────────────
  /// wandb internally calls projects "models"
  static const getProjects = r'''
query GetProjects($entity: String, $cursor: String, $perPage: Int = 50) {
  models(entityName: $entity, after: $cursor, first: $perPage) {
    pageInfo {
      endCursor
      hasNextPage
    }
    edges {
      node {
        id
        name
        entityName
        createdAt
        isBenchmark
        description
        user {
          name
          username
        }
      }
    }
  }
}
''';

  static const getProject = r'''
query GetProject($name: String!, $entity: String!) {
  project(name: $name, entityName: $entity) {
    id
    name
    entityName
    createdAt
    isBenchmark
    description
    user {
      name
      username
    }
  }
}
''';

  // ─── Runs ──────────────────────────────────────────────
  static const getRuns = r'''
query Runs($project: String!, $entity: String!, $cursor: String,
           $perPage: Int = 50, $order: String, $filters: JSONString) {
  project(name: $project, entityName: $entity) {
    runCount(filters: $filters)
    readOnly
    runs(filters: $filters, after: $cursor, first: $perPage, order: $order) {
      edges {
        node {
          id
          tags
          name
          displayName
          sweepName
          state
          config
          group
          jobType
          commit
          readOnly
          createdAt
          heartbeatAt
          description
          notes
          systemMetrics
          summaryMetrics
          historyLineCount
          user {
            name
            username
          }
          historyKeys
        }
        cursor
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
  }
}
''';

  // ─── Run History (Sampled — for charts) ────────────────
  /// $spec format: {"keys": ["loss", "accuracy"], "samples": 500}
  /// Returns array of arrays, each element is {"_step": N, "loss": 0.5, ...}
  static const getSampledHistory = r'''
query SampledHistoryPage($entity: String!, $project: String!,
                          $run: String!, $spec: JSONString!) {
  project(name: $project, entityName: $entity) {
    run(name: $run) {
      sampledHistory(specs: [$spec])
    }
  }
}
''';

  // ─── Run History (Full — for zoom-in precision) ────────
  static const getHistoryPage = r'''
query HistoryPage($entity: String!, $project: String!, $run: String!,
                  $minStep: Int64!, $maxStep: Int64!, $pageSize: Int!) {
  project(name: $project, entityName: $entity) {
    run(name: $run) {
      history(minStep: $minStep, maxStep: $maxStep, samples: $pageSize)
    }
  }
}
''';

  // ─── System Metrics (CPU, GPU, Memory over time) ───────
  static const getRunEvents = r'''
query RunEvents($project: String!, $entity: String!, $name: String!,
                $samples: Int!) {
  project(name: $project, entityName: $entity) {
    run(name: $name) {
      events(samples: $samples)
    }
  }
}
''';

  // ─── Run Files ─────────────────────────────────────────
  /// Use fileNames: ["output.log"] to get console logs
  /// directUrl can be used to download files directly
  static const getRunFiles = r'''
query RunFiles($project: String!, $entity: String!, $name: String!,
               $fileCursor: String, $fileLimit: Int = 50,
               $fileNames: [String] = []) {
  project(name: $project, entityName: $entity) {
    run(name: $name) {
      fileCount
      files(names: $fileNames, after: $fileCursor, first: $fileLimit) {
        edges {
          node {
            id
            name
            url(upload: false)
            directUrl
            sizeBytes
            mimetype
            updatedAt
            md5
          }
          cursor
        }
        pageInfo {
          endCursor
          hasNextPage
        }
      }
    }
  }
}
''';

  // ─── Sweeps ────────────────────────────────────────────
  static const getSweeps = r'''
query GetSweeps($project: String!, $entity: String!, $cursor: String,
                $perPage: Int = 50) {
  project(name: $project, entityName: $entity) {
    totalSweeps
    sweeps(after: $cursor, first: $perPage) {
      pageInfo {
        endCursor
        hasNextPage
      }
      edges {
        node {
          id
          name
          displayName
          method
          state
          description
          bestLoss
          config
          createdAt
          updatedAt
          runCount
          runCountExpected
        }
      }
    }
  }
}
''';

  static const getSweep = r'''
query GetSweep($name: String!, $project: String, $entity: String) {
  project(name: $project, entityName: $entity) {
    sweep(sweepName: $name) {
      id
      name
      displayName
      method
      state
      description
      bestLoss
      config
      createdAt
      updatedAt
      runCount
      runCountExpected
    }
  }
}
''';
}
