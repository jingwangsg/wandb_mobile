import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app.dart';
import 'core/diagnostics/runtime_diagnostics.dart';
import 'core/providers/mobile_preferences.dart';
import 'features/charts/data/run_chart_preferences_store.dart';
import 'features/notifications/data/push_service.dart';
import 'core/app_configuration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RunChartPreferencesStore.initialize();
  await Hive.openBox<String>(MobilePreferencesStore.boxName);
  if (AppConfiguration.pushConfigured) {
    await initializeFirebase();
    FirebaseMessaging.onBackgroundMessage(receiveBackgroundPush);
  }
  await RuntimeDiagnostics.instance.initialize();
  RuntimeDiagnostics.instance.installFlutterHandlers();

  runZonedGuarded(
    () {
      runApp(const ProviderScope(child: WandbApp()));
    },
    (error, stackTrace) {
      RuntimeDiagnostics.instance.record(
        'zone_error',
        error.toString(),
        stackTrace: stackTrace,
      );
    },
  );
}
