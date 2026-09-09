import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wandb_mobile/features/auth/providers/auth_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Preparing local test session'))),
    ),
  );
  final socket = await Socket.connect(
    '10.0.2.2',
    int.parse(const String.fromEnvironment('SESSION_PORT')),
  );
  socket.writeln(const String.fromEnvironment('SESSION_NONCE'));
  await socket.flush();
  final payload =
      jsonDecode(await utf8.decoder.bind(socket).join())
          as Map<String, dynamic>;
  final container = ProviderContainer();
  final ready = Completer<void>();
  final subscription = container.listen(authStatusProvider, (_, status) {
    if (status != AuthStatus.loading && !ready.isCompleted) ready.complete();
  }, fireImmediately: true);
  await ready.future.timeout(const Duration(seconds: 45));
  subscription.close();
  await container
      .read(authProvider.notifier)
      .login(apiKey: payload['apiKey'] as String, preselectedEntity: 'nv-gear');
  final auth = container.read(authProvider);
  final message =
      auth.status == AuthStatus.authenticated
          ? 'Session ready: ${auth.user!.username}'
          : 'Session failed: ${auth.error}';
  debugPrint('[emulator-session] $message');
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text(message)))));
}
