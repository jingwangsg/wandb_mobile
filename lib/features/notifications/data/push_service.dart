import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_configuration.dart';
import '../../../core/providers/api_client_provider.dart';
import '../../auth/data/secure_storage_service.dart';
import '../../auth/providers/auth_providers.dart';
import 'notifications_repository.dart';

Future<void> initializeFirebase() async {
  if (!AppConfiguration.pushConfigured || Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: AppConfiguration.firebaseApiKey,
      appId: AppConfiguration.firebaseAppId,
      messagingSenderId: AppConfiguration.firebaseSenderId,
      projectId: AppConfiguration.firebaseProjectId,
    ),
  );
}

@pragma('vm:entry-point')
Future<void> receiveBackgroundPush(RemoteMessage message) async {
  await initializeFirebase();
  await FlutterLocalNotificationsPlugin().initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    ),
  );
  await displayPush(message);
}

Future<void> displayPush(RemoteMessage message) async {
  final storage = SecureStorageService();
  final owner = message.data['owner'];
  final eventId = message.data['eventId'];
  if (owner == null ||
      owner != await storage.getUserId() ||
      !await storage.getPushEnabled(userId: owner) ||
      eventId == null ||
      eventId.length < 8) {
    return;
  }
  final id = int.tryParse(eventId.substring(0, 8), radix: 16);
  if (id == null) return;
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.show(
    id: id & 0x7fffffff,
    title: message.data['title'] ?? 'W&B',
    body: message.data['body'],
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'wandb_runs',
        'Training runs',
        channelDescription: 'Run failures and metric changes',
        importance: Importance.high,
        priority: Priority.high,
        tag: eventId,
      ),
    ),
    payload: jsonEncode(message.data),
  );
  if (owner != await storage.getUserId() ||
      !await storage.getPushEnabled(userId: owner)) {
    await notifications.cancel(id: id & 0x7fffffff, tag: eventId);
  }
}

String? notificationRoute(Map<String, dynamic> data, String? userId) {
  if (userId == null || data['owner'] != userId) return null;
  final entity = data['entity'];
  final project = data['project'];
  final run = data['run'];
  if ([entity, project, run].any((value) => value is! String || value.isEmpty))
    return null;
  return '/projects/${Uri.encodeComponent(entity as String)}/${Uri.encodeComponent(project as String)}/runs/${Uri.encodeComponent(run as String)}';
}

final pendingNotificationRouteProvider = StateProvider<String?>((ref) => null);

class PushPlatform {
  bool get configured => AppConfiguration.pushConfigured;
  Stream<String> get tokenRefreshes =>
      FirebaseMessaging.instance.onTokenRefresh;
  Stream<RemoteMessage> get messages => FirebaseMessaging.onMessage;
  Stream<RemoteMessage> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp;

  Future<String> initialize(
    void Function(Map<String, dynamic>) onOpen, {
    required bool requestPermission,
  }) async {
    await initializeFirebase();
    if (requestPermission) {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied)
        throw StateError(
          'Allow notifications in Android settings to enable alerts.',
        );
    }
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null)
          onOpen(jsonDecode(response.payload!) as Map<String, dynamic>);
      },
    );
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'wandb_runs',
            'Training runs',
            description: 'Run failures and metric changes',
            importance: Importance.high,
          ),
        );
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null)
      throw StateError('Unable to register this device with Firebase.');
    return token;
  }

  Future<Map<String, dynamic>?> initialMessage() async {
    final launch =
        await FlutterLocalNotificationsPlugin()
            .getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && payload != null)
      return jsonDecode(payload) as Map<String, dynamic>;
    return (await FirebaseMessaging.instance.getInitialMessage())?.data;
  }

  Future<void> deleteToken() async {
    if (configured && Firebase.apps.isNotEmpty)
      await FirebaseMessaging.instance.deleteToken();
  }

  Future<void> clearNotifications() =>
      FlutterLocalNotificationsPlugin().cancelAll();
  Future<void> show(RemoteMessage message) => displayPush(message);
}

class PushService extends StateNotifier<AsyncValue<bool>> {
  PushService(
    this._repository,
    this._storage,
    this._userId,
    this._onOpen, {
    PushPlatform? platform,
  }) : _platform = platform ?? PushPlatform(),
       super(const AsyncValue.loading()) {
    _restore();
  }

  final NotificationsRepository _repository;
  final SecureStorageService _storage;
  final String? _userId;
  final void Function(Map<String, dynamic>) _onOpen;
  final PushPlatform _platform;
  final _registrations = <String>{};
  StreamSubscription<String>? _tokens;
  StreamSubscription<RemoteMessage>? _messages;
  StreamSubscription<RemoteMessage>? _opened;
  Future<void>? _activation;
  Future<void>? _deactivation;
  Future<void> _rotation = Future.value();
  Completer<void> _interrupted = Completer<void>();
  String? _token;
  int _generation = 0;

  Future<void> _restore() async {
    final generation = _generation;
    try {
      final enabled =
          _platform.configured &&
          _userId != null &&
          await _storage.getPushEnabled(userId: _userId);
      if (!mounted || generation != _generation) return;
      state = AsyncValue.data(enabled);
      if (enabled) await enable(requestPermission: false);
    } catch (error, stack) {
      if (mounted && generation == _generation)
        state = AsyncValue<bool>.error(error, stack).copyWithPrevious(state);
    }
  }

  Future<void> enable({bool requestPermission = true}) {
    if (_deactivation != null)
      return _deactivation!.then(
        (_) => enable(requestPermission: requestPermission),
      );
    if (_activation != null) return _activation!;
    final operation = _activate(requestPermission: requestPermission);
    _activation = operation;
    return operation.whenComplete(() {
      if (identical(_activation, operation)) _activation = null;
    });
  }

  Future<void> _activate({required bool requestPermission}) async {
    if (!_platform.configured)
      throw StateError('Push notifications are not configured for this build.');
    if (_userId == null) throw StateError('Sign in to enable notifications.');
    final generation = ++_generation;
    if (!_interrupted.isCompleted) _interrupted.complete();
    _interrupted = Completer<void>();
    final previous = state;
    state = const AsyncValue<bool>.loading().copyWithPrevious(state);
    try {
      final token = await _platform.initialize((data) {
        if (mounted && generation == _generation) _onOpen(data);
      }, requestPermission: requestPermission);
      if (!mounted || generation != _generation) return;
      final launch = await _platform.initialMessage();
      if (!mounted || generation != _generation) return;
      if (launch != null) _onOpen(launch);
      _token = token;
      _registrations.add(token);
      await _registerDevice(token, generation);
      if (!mounted || generation != _generation) return;
      await _storage.setPushEnabled(true, userId: _userId);
      if (!mounted || generation != _generation) return;
      await _tokens?.cancel();
      await _messages?.cancel();
      await _opened?.cancel();
      if (!mounted || generation != _generation) return;
      _tokens = _platform.tokenRefreshes.listen((newToken) {
        _rotation = _rotation
            .then((_) async {
              if (!mounted || generation != _generation) return;
              final previous = _token;
              _token = newToken;
              _registrations.add(newToken);
              await _registerDevice(newToken, generation);
              if (!mounted || generation != _generation) return;
              if (previous != null && previous != newToken) {
                await _repository.unregisterDevice(previous);
                _registrations.remove(previous);
              }
              if (mounted && generation == _generation)
                state = const AsyncValue.data(true);
            })
            .catchError((Object error, StackTrace stack) {
              if (mounted && generation == _generation)
                state = AsyncValue<bool>.error(
                  error,
                  stack,
                ).copyWithPrevious(state);
            });
      });
      _messages = _platform.messages.listen((message) {
        if (mounted && generation == _generation) _platform.show(message);
      });
      _opened = _platform.openedMessages.listen((message) {
        if (mounted && generation == _generation) _onOpen(message.data);
      });
      state = const AsyncValue.data(true);
    } catch (error, stack) {
      if (mounted && generation == _generation)
        state = AsyncValue<bool>.error(error, stack).copyWithPrevious(previous);
      rethrow;
    }
  }

  Future<void> _registerDevice(String token, int generation) async {
    // Firebase does not replay a token refresh when the relay becomes reachable.
    final interrupted = _interrupted.future;
    for (var attempt = 0; mounted && generation == _generation; attempt++) {
      try {
        await _repository.registerDevice(token);
        return;
      } on DioException catch (error, stack) {
        if (!mounted || generation != _generation) return;
        final status = error.response?.statusCode;
        final transient =
            [
              DioExceptionType.connectionError,
              DioExceptionType.connectionTimeout,
              DioExceptionType.sendTimeout,
              DioExceptionType.receiveTimeout,
            ].contains(error.type) ||
            status == 429 ||
            (status != null && status >= 500);
        if (!transient) rethrow;
        state = AsyncValue<bool>.error(
          error,
          stack,
        ).copyWithPrevious(const AsyncValue.data(true));
        final resume = Completer<void>();
        final timer = Timer(
          Duration(seconds: attempt < 5 ? 1 << attempt : 30),
          resume.complete,
        );
        try {
          await Future.any([resume.future, interrupted]);
        } finally {
          timer.cancel();
        }
      }
    }
  }

  Future<void> disable() {
    if (_deactivation != null) return _deactivation!;
    _generation++;
    if (!_interrupted.isCompleted) _interrupted.complete();
    if (mounted)
      state = const AsyncValue<bool>.loading().copyWithPrevious(state);
    final operation = _deactivate();
    _deactivation = operation;
    return operation.whenComplete(() {
      if (identical(_deactivation, operation)) _deactivation = null;
    });
  }

  Future<void> _deactivate() async {
    Object? failure;
    StackTrace? failureStack;
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    await attempt(_platform.clearNotifications);
    await _tokens?.cancel();
    await _messages?.cancel();
    await _opened?.cancel();
    try {
      await _activation;
    } catch (_) {
      /* Activation errors must not prevent cleanup. */
    }
    await _rotation;
    await attempt(() => _storage.setPushEnabled(false, userId: _userId));
    await attempt(_platform.deleteToken);
    await attempt(_platform.clearNotifications);
    for (final token in _registrations.toList()) {
      await attempt(() => _repository.unregisterDevice(token));
    }
    _registrations.clear();
    _token = null;
    if (mounted) state = const AsyncValue.data(false);
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }

  @override
  void dispose() {
    _generation++;
    if (!_interrupted.isCompleted) _interrupted.complete();
    _tokens?.cancel();
    _messages?.cancel();
    _opened?.cancel();
    super.dispose();
  }
}

final pushServiceProvider =
    StateNotifierProvider<PushService, AsyncValue<bool>>((ref) {
      final userId = ref.watch(authProvider.select((auth) => auth.user?.id));
      return PushService(
        ref.watch(notificationsRepositoryProvider),
        ref.watch(secureStorageProvider),
        userId,
        (data) {
          final path = notificationRoute(data, userId);
          if (path != null)
            ref.read(pendingNotificationRouteProvider.notifier).state = path;
        },
      );
    });
