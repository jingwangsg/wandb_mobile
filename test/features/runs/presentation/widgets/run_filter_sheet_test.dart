import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/core/models/resource_refs.dart';
import 'package:wandb_mobile/features/runs/models/run_filters.dart';
import 'package:wandb_mobile/features/runs/presentation/widgets/run_filter_sheet.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

void main() {
  const projectRef = ProjectRef(entity: 'entity', project: 'project');

  testWidgets('renders web-like filter rows and applies AND conditions', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: RunFilterSheet(projectRef: projectRef)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New filter'), findsOneWidget);
    expect(find.textContaining('All rows are combined with AND'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('filter-value-tags')).first, 'single_turn');
    await tester.pump();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final filters = container.read(runFiltersProvider(projectRef));
    expect(filters.advancedFilterRoot?.logic, RunFilterLogic.and);
    expect(filters.advancedFilterRoot?.children.length, 1);
    final condition = filters.advancedFilterRoot?.children.first as RunFilterCondition;
    expect(condition.fieldPath, 'tags');
    expect(condition.operator, RunFilterOperator.inList);
    expect(condition.rawValue, 'single_turn');
  });

  testWidgets('shows unsupported message for nested or filters', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(runFiltersProvider(projectRef).notifier).applyAdvancedFilter(
      const RunFilterGroup(
        logic: RunFilterLogic.or,
        children: [
          RunFilterCondition(
            fieldPath: 'state',
            operator: RunFilterOperator.eq,
            valueType: RunFilterValueType.text,
            rawValue: 'crashed',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: RunFilterSheet(projectRef: projectRef)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot be edited in this simplified view'), findsOneWidget);
  });
}
