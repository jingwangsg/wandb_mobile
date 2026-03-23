import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/features/runs/presentation/widgets/run_filter_sheet.dart';
import 'package:wandb_mobile/features/runs/providers/runs_providers.dart';

void main() {
  testWidgets(
    'disables apply until a condition is complete and applies filter',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: RunFilterSheet(projectPath: 'entity/project')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('add-condition-root')));
      await tester.pumpAndSettle();

      FilledButton applyButton() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      );

      expect(applyButton().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('field-root-0')),
        'state',
      );
      await tester.pumpAndSettle();
      expect(applyButton().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('value-root-0')),
        'finished',
      );
      await tester.pumpAndSettle();
      expect(applyButton().onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      final filters = container.read(runFiltersProvider('entity/project'));
      expect(filters.advancedFilterCount, 1);
      expect(filters.toApiFilters(), {'state': 'finished'});
    },
  );
}
