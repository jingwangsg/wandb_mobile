import 'package:flutter_test/flutter_test.dart';
import 'package:wandb_mobile/features/charts/models/panel_spec.dart';

void main() {
  const catalog = ['train/loss', 'train/acc', 'eval/loss', 'lr'];

  test('an auto panel is keyed by its metric and sectioned by prefix', () {
    final panel = PanelSpec.metric('train/loss');
    expect(panel.isAuto, true);
    expect(panel.section, 'train');
    expect(panel.displayTitle, 'train/loss');
    expect(PanelSpec.metric('lr').section, 'Charts');
  });

  test(
    'web panels carry metrics, an opt-in regex, expressions and a title',
    () {
      final panel = PanelSpec.fromWeb('Evaluation', {
        '__id__': 'abc',
        'config': {
          'chartTitle': 'Losses',
          'metrics': ['train/loss'],
          'metricRegex': r'.*/loss',
          'useMetricRegex': true,
          'expressions': [r'${train/loss} * 2', 'bad ('],
        },
      });
      expect(panel.id, 'abc');
      expect(panel.section, 'Evaluation');
      expect(panel.isAuto, false);
      expect(panel.displayTitle, 'Losses');
      expect(panel.resolveMetrics(catalog), ['train/loss', 'eval/loss']);
      expect(panel.validExpressions.map((e) => e.source), [
        r'${train/loss} * 2',
      ]);

      final regexOff = PanelSpec.fromWeb('S', {
        '__id__': 'x',
        'config': {
          'metrics': ['lr'],
          'metricRegex': '.*',
          'useMetricRegex': false,
        },
      });
      expect(regexOff.metricRegex, isNull);
      expect(regexOff.isSingleMetric, true);
      expect(regexOff.isAuto, false, reason: 'the id is not the metric');
    },
  );

  test(
    'an invalid regex matches nothing and the title falls back to parts',
    () {
      const panel = PanelSpec(
        id: 'p',
        section: 'Custom',
        metrics: ['lr'],
        metricRegex: '(',
        expressions: [r'${lr} * 2'],
      );
      expect(panel.resolveMetrics(catalog), ['lr']);
      expect(panel.displayTitle, r'lr, /(/, ${lr} * 2');
    },
  );

  test('app panels round-trip through JSON and compare by value', () {
    const panel = PanelSpec(
      id: 'panel-1',
      section: 'Custom',
      title: 'Mine',
      metrics: ['a', 'b'],
      metricRegex: 'c.*',
      expressions: [r'${a} - ${b}'],
    );
    expect(PanelSpec.fromJson(panel.toJson()), panel);
    expect(panel, isNot(const PanelSpec(id: 'panel-1', section: 'Custom')));
  });
}
