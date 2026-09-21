import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/run_file.dart';
import 'package:wandb_mobile/features/runs/data/runs_repository.dart';

class RecordingGraphqlClient extends GraphqlClient {
  RecordingGraphqlClient(this._handler) : super(apiKey: 'test');

  final FutureOr<Map<String, dynamic>> Function(
    String query,
    Map<String, dynamic>? variables,
  )
  _handler;

  String? lastQuery;
  Map<String, dynamic>? lastVariables;

  @override
  Future<Map<String, dynamic>> query(
    String queryString, {
    Map<String, dynamic>? variables,
  }) async {
    lastQuery = queryString;
    lastVariables = variables;
    return await _handler(queryString, variables);
  }
}

void main() {
  group('RunsRepository.getRuns', () {
    test('encodes filters as JSONString variables', () async {
      final client = RecordingGraphqlClient((_, __) async {
        return {
          'project': {
            'runCount': 0,
            'runs': {
              'edges': const [],
              'pageInfo': {'endCursor': null, 'hasNextPage': false},
            },
          },
        };
      });
      final repository = RunsRepository(client);

      await repository.getRuns(
        entity: 'entity',
        project: 'project',
        order: '-created_at',
        filters: {
          r'$or': [
            {'state': 'running'},
            {'group': 'exp-a'},
          ],
        },
      );

      expect(
        client.lastVariables?['filters'],
        jsonEncode({
          r'$or': [
            {'state': 'running'},
            {'group': 'exp-a'},
          ],
        }),
      );
      expect(client.lastVariables?['order'], '-created_at');
    });
  });

  group('RunsRepository.getWorkspaceSettings', () {
    test(
      'returns the personal workspace and null when there is none',
      () async {
        final client = RecordingGraphqlClient(
          (_, __) async => {
            'project': {
              'allViews': {
                'edges': [
                  {
                    'node': {
                      'id': 'v',
                      'name': 'nw-abc-v',
                      'spec': jsonEncode({
                        'section': {
                          'workspaceSettings': {
                            'linePlot': {'xAxis': '_runtime'},
                          },
                        },
                      }),
                    },
                  },
                  {
                    'node': {
                      'id': 'w',
                      'name': 'nw-nwuseralice-w',
                      'spec': jsonEncode({
                        'section': {
                          'workspaceSettings': {
                            'linePlot': {'xAxis': 'epoch', 'maxRuns': 3},
                          },
                        },
                      }),
                    },
                  },
                ],
              },
            },
          },
        );
        final settings = await RunsRepository(client).getWorkspaceSettings(
          entity: 'entity',
          project: 'project',
          username: 'alice',
        );
        expect(client.lastVariables, {
          'entity': 'entity',
          'project': 'project',
          'username': 'alice',
        });
        expect(settings?.linePlot['xAxis'], 'epoch');
        expect(settings?.maxRuns, 3);

        final empty = RunsRepository(
          RecordingGraphqlClient(
            (_, __) async => {
              'project': {
                'allViews': {'edges': const []},
              },
            },
          ),
        );
        expect(
          await empty.getWorkspaceSettings(
            entity: 'entity',
            project: 'project',
            username: 'alice',
          ),
          isNull,
        );
      },
    );
  });

  group('RunsRepository.getBucketedHistory', () {
    test('buckets along the chosen axis and keeps each bucket band', () async {
      final client = RecordingGraphqlClient((_, variables) async {
        expect((variables!['specs'] as List<dynamic>).cast<String>(), [
          jsonEncode({
            'keys': ['loss'],
            'samples': 300,
            'xAxis': '_timestamp',
          }),
        ]);
        return {
          'project': {
            'run': {
              'bucketedHistory': [
                [
                  {
                    'bucketSize': 2,
                    '_stepAvg': 5,
                    '_timestampAvg': 1700000000,
                    'lossAvg': 0.9,
                    'lossMin': 0.8,
                    'lossMax': 1.0,
                  },
                  {
                    'bucketSize': 1,
                    '_stepAvg': 9,
                    '_timestampAvg': 1700000010,
                    'lossAvg': null,
                    'lossMin': null,
                    'lossMax': null,
                  },
                  {
                    'bucketSize': 3,
                    '_stepAvg': 12,
                    '_timestampAvg': 1700000020,
                    'lossAvg': 0.7,
                    'lossMin': 0.6,
                    'lossMax': 0.75,
                  },
                ],
              ],
            },
          },
        };
      });
      final series = await RunsRepository(client).getBucketedHistory(
        entity: 'entity',
        project: 'project',
        runName: 'run',
        keys: ['loss'],
        xAxis: '_timestamp',
      );
      expect(
        series.single.points.map(
          (point) => (point.x, point.value, point.low, point.high),
        ),
        [(1700000000000.0, 0.9, 0.8, 1.0), (1700000020000.0, 0.7, 0.6, 0.75)],
        reason: 'empty buckets are skipped and wall time is in milliseconds',
      );
    });
  });

  group('RunsRepository.getSystemMetrics', () {
    test('decodes string and map event rows', () async {
      final client = RecordingGraphqlClient((_, __) async {
        return {
          'project': {
            'run': {
              'events': [
                jsonEncode({
                  '_timestamp': 1700000000,
                  'system': {'cpu': 0.5},
                }),
                {
                  '_timestamp': 1700000001,
                  'system': {'memory': 0.75},
                },
              ],
            },
          },
        };
      });
      final repository = RunsRepository(client);

      final rows = await repository.getSystemMetrics(
        entity: 'entity',
        project: 'project',
        runName: 'run',
        samples: 5,
      );

      expect(rows, hasLength(2));
      expect(rows.first['system'], isA<Map<String, dynamic>>());
      expect((rows.first['system'] as Map<String, dynamic>)['cpu'], 0.5);
      expect((rows.last['system'] as Map<String, dynamic>)['memory'], 0.75);
    });
  });

  group('RunsRepository.getRunFiles', () {
    test('parses files and pagination metadata', () async {
      final client = RecordingGraphqlClient((_, __) async {
        return {
          'project': {
            'run': {
              'fileCount': 12,
              'files': {
                'edges': [
                  {
                    'cursor': 'cursor-1',
                    'node': {
                      'id': 'file-1',
                      'name': 'media/table.table.json',
                      'url': 'https://example.com/file-1',
                      'directUrl': 'https://example.com/direct-file-1',
                      'sizeBytes': 128,
                      'mimetype': 'application/json',
                      'updatedAt': '2024-01-01T00:00:00Z',
                      'md5': 'abc123',
                    },
                  },
                ],
                'pageInfo': {'endCursor': 'cursor-1', 'hasNextPage': true},
              },
            },
          },
        };
      });
      final repository = RunsRepository(client);

      final result = await repository.getRunFiles(
        entity: 'entity',
        project: 'project',
        runName: 'run',
      );

      expect(result.totalCount, 12);
      expect(result.endCursor, 'cursor-1');
      expect(result.hasNextPage, isTrue);
      expect(result.items, [
        isA<RunFile>()
            .having((file) => file.id, 'id', 'file-1')
            .having((file) => file.name, 'name', 'media/table.table.json')
            .having(
              (file) => file.directUrl,
              'directUrl',
              'https://example.com/direct-file-1',
            )
            .having((file) => file.sizeBytes, 'sizeBytes', 128)
            .having(
              (file) => file.updatedAt,
              'updatedAt',
              DateTime.parse('2024-01-01T00:00:00Z'),
            ),
      ]);
    });
  });
}
