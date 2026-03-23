import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
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
  group('RunsRepository.getSampledHistory', () {
    test('requests chart axis keys and preserves sampled steps', () async {
      final client = RecordingGraphqlClient((_, variables) {
        final spec =
            jsonDecode(variables!['spec'] as String) as Map<String, dynamic>;
        final keys = (spec['keys'] as List).cast<String>();
        final includeStep = keys.contains('_step');
        final includeTimestamp = keys.contains('_timestamp');

        final rows = [
          {
            if (includeStep) '_step': 10,
            if (includeTimestamp) '_timestamp': 1700000000,
            'loss': 0.5,
          },
          {
            if (includeStep) '_step': 20,
            if (includeTimestamp) '_timestamp': 1700003600,
            'loss': 0.25,
          },
        ];

        return {
          'project': {
            'run': {
              'sampledHistory': [rows],
            },
          },
        };
      });
      final repository = RunsRepository(client);

      final series = await repository.getSampledHistory(
        entity: 'entity',
        project: 'project',
        runName: 'run',
        keys: ['loss'],
        samples: 2,
      );

      final spec =
          jsonDecode(client.lastVariables!['spec'] as String)
              as Map<String, dynamic>;
      expect(spec['keys'], ['_step', '_timestamp', 'loss']);
      expect(series, [
        isA<MetricSeries>()
            .having((value) => value.key, 'key', 'loss')
            .having((value) => value.points.length, 'point count', 2)
            .having((value) => value.points[0].step, 'first step', 10)
            .having((value) => value.points[1].step, 'second step', 20)
            .having(
              (value) => value.points[0].timestamp,
              'first timestamp',
              DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
            ),
      ]);
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
