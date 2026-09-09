import 'dart:convert';
import 'dart:math' as math;

import 'package:wandb_mobile/core/api/graphql_client.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/features/aria/data/aria_repository.dart';
import 'package:wandb_mobile/features/notifications/data/notifications_repository.dart';

class AppFixtureClient extends GraphqlClient {
  AppFixtureClient() : super(apiKey: 'fixture-key');
  final starred = <String>{'rlhf-reward-optimization'};
  final requests = <String>[];

  static const names = [
    'llama-sft-customer-support',
    'rlhf-reward-optimization',
    'scaling-benchmark-a100',
    'gpt2-pretrain-openwebtext',
    'yolo-coco-finetune',
  ];
  static const metrics = ['train/loss', 'eval/loss'];
  static const historyKeys = {
    'lastStep': 800,
    'keys': {
      'train/loss': {
        'typeCounts': [
          {'type': 'number', 'count': 800},
        ],
      },
      'eval/loss': {
        'typeCounts': [
          {'type': 'number', 'count': 800},
        ],
      },
      'system/cpu': {
        'typeCounts': [
          {'type': 'number', 'count': 20},
        ],
      },
      'system/gpu.0.gpu': {
        'typeCounts': [
          {'type': 'number', 'count': 20},
        ],
      },
    },
  };

  Map<String, dynamic> project(String name) => {
    'id': 'project-$name',
    'name': name,
    'entityName': 'wandb',
    'starred': starred.contains(name),
    'lastActive': DateTime.utc(2026, 9, 9, 7).toIso8601String(),
    'runCount': 2,
  };
  Map<String, dynamic> run(
    int index, [
    String projectName = 'llama-sft-customer-support',
  ]) => {
    'id': 'run-id-$index',
    'name': 'run-$index',
    'displayName': 'experiment-$index',
    'state': 'finished',
    'createdAt': '2026-09-09T06:00:00Z',
    'heartbeatAt': '2026-09-09T07:00:00Z',
    'project': {'name': projectName, 'entityName': 'wandb'},
    'user': {'username': 'alice'},
    'historyKeys': historyKeys,
    'summaryMetrics': {'train/loss': 0.12, 'eval/loss': 0.18},
    'config': {
      'learning_rate': {'value': 0.0003},
      'model': {
        'value': {'layers': 24, 'hidden_size': 2048},
      },
    },
  };
  Map<String, dynamic> connection(List<Map<String, dynamic>> items) => {
    'edges': items.map((item) => {'node': item}).toList(),
    'pageInfo': {'endCursor': null, 'hasNextPage': false},
  };

  @override
  Future<Map<String, dynamic>> query(
    String queryString, {
    Map<String, dynamic>? variables,
  }) async {
    final name =
        RegExp(
          r'(?:query|mutation)\s+(\w+)',
        ).firstMatch(queryString)!.group(1)!;
    requests.add(name);
    switch (name) {
      case 'GetViewer':
        return {
          'viewer': {
            'id': 'fixture-user',
            'username': 'alice',
            'name': 'Alice',
            'email': 'alice@example.com',
            'entity': 'alice',
            'teams': {
              'edges': [
                {
                  'node': {'name': 'wandb'},
                },
              ],
            },
          },
        };
      case 'GetProjects':
        return {'models': connection(names.map(project).toList())};
      case 'MobileSearchProjects':
        return {
          'projects': connection(
            names
                .where(
                  (name) =>
                      name.contains(variables!['pattern'] as String? ?? ''),
                )
                .map(project)
                .toList(),
          ),
        };
      case 'MobileStarredProjects':
        return {
          'viewer': {
            'starredProjects': connection(
              names.where(starred.contains).map(project).toList(),
            ),
          },
        };
      case 'MobileStarProject':
        starred.add(variables!['project'] as String);
        return {
          'starProject': {
            'project': {'id': 'project', 'starred': true},
          },
        };
      case 'MobileUnstarProject':
        starred.remove(variables!['project']);
        return {
          'unstarProject': {
            'project': {'id': 'project', 'starred': false},
          },
        };
      case 'MobileRecentRuns':
        return {
          'viewer': {
            'runs': connection([run(1), run(2)]),
          },
        };
      case 'Runs':
        return {
          'project': {
            'runCount': 2,
            'runs': connection([
              run(1, variables!['project'] as String),
              run(2, variables['project'] as String),
            ]),
          },
        };
      case 'MobileRun':
        return {
          'project': {'run': run(1, variables!['project'] as String)},
        };
      case 'MobileProjectMetrics':
        return {
          'project': {
            'runs': {'historyKeys': historyKeys},
          },
        };
      case 'SampledHistoryPage':
        return {
          'project': {
            'run': {
              'sampledHistory':
                  (variables!['specs'] as List).map((spec) {
                    final key =
                        (jsonDecode(spec as String)['keys'] as List).last
                            as String;
                    if (key.startsWith('system/'))
                      throw StateError(
                        'System metrics belong to events, not training history',
                      );
                    return [
                      for (var step = 0; step <= 800; step += 10)
                        {
                          '_step': step,
                          '_timestamp': 1700000000 + step,
                          key:
                              0.8 * math.exp(-step / 250) +
                              (variables['run'] == 'run-2' ? 0.18 : 0.12) +
                              0.015 * math.sin(step / 17),
                        },
                    ];
                  }).toList(),
            },
          },
        };
      case 'RunEvents':
        return {
          'project': {
            'run': {
              'events': [
                for (var step = 0; step < 20; step++)
                  {
                    '_step': step,
                    '_timestamp': 1700000000 + step * 15,
                    'system.gpu.0.gpu': 85 + step % 8,
                    'system.cpu': 32 + step % 4,
                  },
              ],
            },
          },
        };
      case 'MobileRunLogs':
        return {
          'project': {
            'run': {
              'logLines': {
                'edges': [
                  for (var index = 0; index < 6; index++)
                    {
                      'cursor': 'line-$index',
                      'node': {
                        'line':
                            'step=${index * 100} loss=${(0.9 - index * 0.1).toStringAsFixed(4)}',
                        'number': index,
                      },
                    },
                ],
                'pageInfo': {
                  'startCursor': 'line-0',
                  'endCursor': 'line-5',
                  'hasPreviousPage': false,
                  'hasNextPage': false,
                },
              },
            },
          },
        };
      case 'RunFiles':
        return {
          'project': {
            'run': {'fileCount': 0, 'files': connection([])},
          },
        };
      default:
        throw StateError('Unexpected fixture operation: $name');
    }
  }
}

class FixtureAriaRepository extends AriaRepository {
  FixtureAriaRepository() : super(apiKey: 'fixture-key');
  final parentIds = <String?>[];
  final recordedTurns = <String, AriaTurn>{};
  @override
  Future<AriaTurn> createTurn(
    String prompt, {
    ProjectRef? project,
    String? parentId,
    List<Map<String, dynamic>> references = const [],
  }) async {
    parentIds.add(parentId);
    final turn = AriaTurn({
      'id': 'turn-${parentIds.length}',
      'thread_id': 'thread-1',
      'state': 'completed',
      'user_prompt': prompt,
      'messages': [
        {
          'role': 'assistant',
          'content':
              'Your two training runs have completed.\n\n| Run | Loss |\n| --- | --- |\n| experiment-1 | 0.12 |\n| experiment-2 | 0.18 |',
          'message': {},
        },
      ],
      'tool_calls': [],
    });
    recordedTurns[turn.id] = turn;
    return turn;
  }

  @override
  Future<AriaTurn> getTurn(String id, {dynamic cancelToken}) async =>
      recordedTurns[id]!;
}

class FixtureNotificationsRepository extends NotificationsRepository {
  FixtureNotificationsRepository()
    : super(apiKey: 'fixture-key', baseUrl: 'https://push.example.com');
  final items = <NotificationRule>[
    const NotificationRule(
      id: 'rule-1',
      entity: 'wandb',
      project: 'llama-sft-customer-support',
      name: 'Run failed',
    ),
  ];
  @override
  Future<List<NotificationRule>> rules() async => List.of(items);
  @override
  Future<void> delete(String id) async =>
      items.removeWhere((item) => item.id == id);
}
