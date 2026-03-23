import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/features/runs/presentation/widgets/config_viewer.dart';

void main() {
  testWidgets('opens fullscreen viewer with formatted json content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConfigViewer(
            config: {'payload': '{"foo":1,"bar":{"baz":true}}'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.open_in_full), findsOneWidget);

    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();

    expect(find.text('payload'), findsWidgets);
    expect(find.textContaining('"foo": 1'), findsOneWidget);
    expect(find.textContaining('"baz": true'), findsOneWidget);
  });
}
