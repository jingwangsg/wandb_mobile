import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/metric_point.dart';
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
}
