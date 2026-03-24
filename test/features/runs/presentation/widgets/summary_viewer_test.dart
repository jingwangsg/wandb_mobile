import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/features/runs/presentation/widgets/summary_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping summary key copies key text', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SummaryViewer(metrics: {'loss': 0.123456}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('loss'));
    await tester.pump();

    expect(copied, 'loss');
  });

  testWidgets('tapping summary value copies full primitive value', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SummaryViewer(metrics: {'loss': 0.123456}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('0.1235'));
    await tester.pump();

    expect(copied, '0.123456');
  });

  testWidgets('tapping summary value copies full structured value', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SummaryViewer(metrics: {'payload': {'foo': true, 'bar': [1, 2]}}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('{foo: true, bar: [1, 2]}'));
    await tester.pump();

    expect(
      copied,
      '''{
  "foo": true,
  "bar": [
    1,
    2
  ]
}''',
    );
  });
}
