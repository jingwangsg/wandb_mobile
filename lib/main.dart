import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/diagnostics/runtime_diagnostics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RuntimeDiagnostics.instance.initialize();
  RuntimeDiagnostics.instance.installFlutterHandlers();

  runZonedGuarded(() {
    runApp(
      const ProviderScope(
        child: WandbApp(),
      ),
    );
  }, (error, stackTrace) {
    RuntimeDiagnostics.instance.record(
      'zone_error',
      error.toString(),
      stackTrace: stackTrace,
    );
  });
}
