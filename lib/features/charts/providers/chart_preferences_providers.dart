import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/run_chart_preferences_store.dart';

final runChartPreferencesStoreProvider = Provider<RunChartPreferencesStore>((
  ref,
) {
  return RunChartPreferencesStore();
});
