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
    test(
      'requests one sampled history spec per key and preserves sampled steps',
      () async {
        final client = RecordingGraphqlClient((_, variables) {
          final specs = (variables!['specs'] as List<dynamic>)
              .cast<String>()
              .map((spec) => jsonDecode(spec) as Map<String, dynamic>)
              .toList(growable: false);
          final rows = specs
              .map((spec) {
                final keys = (spec['keys'] as List).cast<String>();
                final includeStep = keys.contains('_step');
                final includeTimestamp = keys.contains('_timestamp');
                final key = keys.last;
                return [
                  {
                    if (includeStep) '_step': 10,
                    if (includeTimestamp) '_timestamp': 1700000000,
                    key: 0.5,
                  },
                  {
                    if (includeStep) '_step': 20,
                    if (includeTimestamp) '_timestamp': 1700003600,
                    key: 0.25,
                  },
                ];
              })
              .toList(growable: false);

          return {
            'project': {
              'run': {'sampledHistory': rows},
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

        final specs = (client.lastVariables!['specs'] as List<dynamic>)
            .cast<String>()
            .map((spec) => jsonDecode(spec) as Map<String, dynamic>)
            .toList(growable: false);
        expect(specs, [
          {
            'keys': ['_step', '_timestamp', 'loss'],
            'samples': 2,
          },
        ]);
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
      },
    );

    test(
      'keeps mixed-cadence keys isolated so one empty spec does not drop others',
      () async {
        final client = RecordingGraphqlClient((_, variables) async {
          final specs = (variables!['specs'] as List<dynamic>)
              .cast<String>()
              .map((spec) => jsonDecode(spec) as Map<String, dynamic>)
              .toList(growable: false);

          expect(specs, [
            {
              'keys': ['_step', '_timestamp', 'train/train/loss'],
              'samples': 5,
            },
            {
              'keys': ['_step', '_timestamp', 'timing/model_forward_avg_ms'],
              'samples': 5,
            },
          ]);

          return {
            'project': {
              'run': {
                'sampledHistory': [
                  [
                    {
                      '_step': 101,
                      '_timestamp': 1700000000,
                      'train/train/loss': 0.125,
                    },
                  ],
                  const [],
                ],
              },
            },
          };
        });
        final repository = RunsRepository(client);

        final series = await repository.getSampledHistory(
          entity: 'entity',
          project: 'project',
          runName: 'run',
          keys: const ['train/train/loss', 'timing/model_forward_avg_ms'],
          samples: 5,
        );

        expect(series, hasLength(2));
        expect(series[0].key, 'train/train/loss');
        expect(series[0].points, hasLength(1));
        expect(series[0].points.first.step, 101);
        expect(series[0].points.first.value, 0.125);
        expect(series[1].key, 'timing/model_forward_avg_ms');
        expect(series[1].points, isEmpty);
      },
    );
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
