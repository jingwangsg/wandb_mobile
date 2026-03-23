import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/features/runs/models/run_filters.dart';

void main() {
  group('RunFilters', () {
    test('serializes nested groups with supported operators', () {
      const filters = RunFilters(
        searchQuery: 'loss',
        advancedFilterRoot: RunFilterGroup(
          logic: RunFilterLogic.and,
          children: [
            RunFilterCondition(
              fieldPath: 'state',
              operator: RunFilterOperator.eq,
              valueType: RunFilterValueType.text,
              rawValue: 'running',
            ),
            RunFilterGroup(
              logic: RunFilterLogic.or,
              children: [
                RunFilterCondition(
                  fieldPath: 'config.lr',
                  operator: RunFilterOperator.gt,
                  valueType: RunFilterValueType.number,
                  rawValue: '0.1',
                ),
                RunFilterCondition(
                  fieldPath: 'tags',
                  operator: RunFilterOperator.inList,
                  valueType: RunFilterValueType.textList,
                  rawValue: 'baseline, production',
                ),
              ],
            ),
          ],
        ),
      );

      expect(filters.toApiFilters(), {
        r'$and': [
          {
            'displayName': {r'$regex': 'loss'},
          },
          {
            r'$and': [
              {'state': 'running'},
              {
                r'$or': [
                  {
                    'config.lr': {r'$gt': 0.1},
                  },
                  {
                    'tags': {
                      r'$in': ['baseline', 'production'],
                    },
                  },
                ],
              },
            ],
          },
        ],
      });
    });

    test('rejects incomplete nested filters', () {
      const root = RunFilterGroup(
        logic: RunFilterLogic.and,
        children: [
          RunFilterCondition(
            fieldPath: 'state',
            operator: RunFilterOperator.eq,
            valueType: RunFilterValueType.text,
            rawValue: '',
          ),
        ],
      );

      expect(root.isValid, isFalse);
      expect(root.toApiFilter(), isNull);
    });
  });
}
