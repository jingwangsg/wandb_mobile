import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/features/runs/presentation/widgets/value_presentation.dart';

void main() {
  test('formats structured values as pretty json full text', () {
    final presentation = ValuePresentation.fromValue({'foo': true, 'bar': [1, 2]});

    expect(presentation.isJson, isTrue);
    expect(presentation.fullText, '{\n  "foo": true,\n  "bar": [\n    1,\n    2\n  ]\n}');
  });

  test('treats long strings as expandable and preserves full text', () {
    const value = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-long-value-extra-padding-12345';
    final presentation = ValuePresentation.fromValue(value);

    expect(presentation.isExpandable, isTrue);
    expect(presentation.fullText, value);
  });
}
