import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wandb_mobile/features/aria/data/aria_repository.dart';
import 'package:wandb_mobile/features/notifications/data/notifications_repository.dart';
import 'package:wandb_mobile/features/notifications/data/push_service.dart';

import 'test_support/mobile_test_support.dart';

class DevicePlatform extends PushPlatform {
  final refreshed = StreamController<String>.broadcast();
  final received = StreamController<RemoteMessage>.broadcast();
  final opened = StreamController<RemoteMessage>.broadcast();
  final visibleNotifications = <String>{'old-notification'};
  bool tokenPresent = true;
  Map<String, dynamic>? launchMessage;
  @override
  bool get configured => true;
  @override
  Stream<String> get tokenRefreshes => refreshed.stream;
  @override
  Stream<RemoteMessage> get messages => received.stream;
  @override
  Stream<RemoteMessage> get openedMessages => opened.stream;
  @override
  Future<String> initialize(
    void Function(Map<String, dynamic>) onOpen, {
    required bool requestPermission,
  }) async => 'device-token';
  @override
  Future<Map<String, dynamic>?> initialMessage() async => launchMessage;
  @override
  Future<void> deleteToken() async {
    tokenPresent = false;
  }

  @override
  Future<void> clearNotifications() async {
    visibleNotifications.clear();
  }

  @override
  Future<void> show(RemoteMessage message) async {
    visibleNotifications.add('new-notification');
  }

  Future<void> close() async {
    await refreshed.close();
    await received.close();
    await opened.close();
  }
}

class DeviceRepository extends NotificationsRepository {
  DeviceRepository({Set<String>? devices})
    : devices = devices ?? {},
      super(apiKey: 'test', baseUrl: 'https://push.example');
  final Set<String> devices;
  Completer<void>? gate;
  String? blockedToken;
  int registrations = 0;
  bool offlineOnDelete = false;
  bool offlineOnRegister = false;
  @override
  Future<void> registerDevice(String token) async {
    registrations++;
    if (offlineOnRegister)
      throw DioException(
        requestOptions: RequestOptions(path: '/v1/devices'),
        type: DioExceptionType.connectionError,
      );
    if (gate != null && (blockedToken == null || blockedToken == token))
      await gate!.future;
    devices.add(token);
  }

  @override
  Future<void> unregisterDevice(String token) async {
    if (offlineOnDelete) throw StateError('relay offline');
    devices.remove(token);
  }
}

class DelayedOptInStorage extends MemorySecureStorage {
  final optIn = Completer<void>();
  @override
  Future<void> setPushEnabled(bool value, {String? userId}) async {
    if (value) await optIn.future;
    await super.setPushEnabled(value, userId: userId);
  }
}

void main() {
  test(
    'a cold-start notification opens while relay registration is pending',
    () async {
      final platform =
          DevicePlatform()
            ..launchMessage = {
              'owner': 'alice',
              'entity': 'team',
              'project': 'training',
              'run': 'run-1',
            };
      final repository = DeviceRepository()..gate = Completer<void>();
      final opened = <String?>[];
      final service = PushService(
        repository,
        MemorySecureStorage()..userId = 'alice',
        'alice',
        (data) => opened.add(notificationRoute(data, 'alice')),
        platform: platform,
      );
      addTearDown(service.dispose);
      addTearDown(platform.close);
      final enable = service.enable();
      try {
        await Future<void>.delayed(Duration.zero);
        expect(repository.registrations, 1);
        expect(opened, ['/projects/team/training/runs/run-1']);
      } finally {
        repository.gate!.complete();
        await enable;
      }
    },
  );

  test(
    'restored push registration recovers after a relay connection failure',
    () async {
      final platform = DevicePlatform();
      final repository = DeviceRepository()..offlineOnRegister = true;
      final storage =
          MemorySecureStorage()
            ..userId = 'alice'
            ..pushEnabled = true;
      final service = PushService(
        repository,
        storage,
        'alice',
        (_) {},
        platform: platform,
      );
      addTearDown(service.dispose);
      addTearDown(platform.close);
      await Future<void>.delayed(Duration.zero);
      expect(service.state.hasError, true);
      expect(repository.devices, isEmpty);
      repository.offlineOnRegister = false;
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(repository.devices, {'device-token'});
      expect(service.state.valueOrNull, true);
      expect(service.state.hasError, false);
    },
  );

  for (final action in ['recover', 'disable', 'dispose']) {
    test(
      'failed token rotation can $action without another token refresh',
      () async {
        final platform = DevicePlatform();
        final repository = DeviceRepository();
        final storage = MemorySecureStorage()..userId = 'alice';
        final service = PushService(
          repository,
          storage,
          'alice',
          (_) {},
          platform: platform,
        );
        if (action != 'dispose') addTearDown(service.dispose);
        addTearDown(platform.close);
        await service.enable();
        repository.offlineOnRegister = true;
        platform.refreshed.add('new-token');
        await Future<void>.delayed(Duration.zero);
        expect(service.state.hasError, true);
        expect(repository.devices, {'device-token'});
        if (action == 'disable') await service.disable();
        if (action == 'dispose') service.dispose();
        final registrations = repository.registrations;
        repository.offlineOnRegister = false;
        await Future<void>.delayed(const Duration(seconds: 2));
        if (action == 'recover') {
          expect(repository.devices, {'new-token'});
          expect(service.state.hasError, false);
        } else {
          expect(
            repository.registrations,
            registrations,
            reason:
                'cancelled registration must not resume when the relay recovers',
          );
          expect(
            repository.devices,
            action == 'disable' ? isEmpty : {'device-token'},
          );
        }
      },
    );
  }

  test(
    'offline remote unregister still removes local notifications and token',
    () async {
      final platform = DevicePlatform();
      final storage = MemorySecureStorage()..userId = 'alice';
      final repository = DeviceRepository();
      final service = PushService(
        repository,
        storage,
        'alice',
        (_) {},
        platform: platform,
      );
      addTearDown(service.dispose);
      addTearDown(platform.close);
      await service.enable();
      repository.offlineOnDelete = true;
      await expectLater(service.disable(), throwsStateError);
      expect(platform.visibleNotifications, isEmpty);
      expect(platform.tokenPresent, false);
      expect(await storage.getPushEnabled(userId: 'alice'), false);
      expect(service.state.valueOrNull, false);
    },
  );

  test('overlapping enable calls register a token only once', () async {
    final platform = DevicePlatform();
    final repository = DeviceRepository()..gate = Completer<void>();
    final service = PushService(
      repository,
      MemorySecureStorage()..userId = 'alice',
      'alice',
      (_) {},
      platform: platform,
    );
    addTearDown(service.dispose);
    addTearDown(platform.close);
    final first = service.enable();
    final second = service.enable();
    await Future<void>.delayed(Duration.zero);
    expect(repository.registrations, 1);
    expect(service.state.isLoading, true);
    repository.gate!.complete();
    await Future.wait([first, second]);
    expect(repository.devices, {'device-token'});
    expect(service.state.valueOrNull, true);
  });

  test(
    'disable waits for an in-flight opt-in write and finishes with opt-out',
    () async {
      final platform = DevicePlatform();
      final repository = DeviceRepository();
      final storage = DelayedOptInStorage()..userId = 'alice';
      final service = PushService(
        repository,
        storage,
        'alice',
        (_) {},
        platform: platform,
      );
      addTearDown(service.dispose);
      addTearDown(platform.close);
      final enable = service.enable();
      await Future<void>.delayed(Duration.zero);
      final disable = service.disable();
      storage.optIn.complete();
      await Future.wait([enable, disable]);
      platform.received.add(const RemoteMessage());
      await Future<void>.delayed(Duration.zero);
      expect(await storage.getPushEnabled(userId: 'alice'), false);
      expect(repository.devices, isEmpty);
      expect(platform.visibleNotifications, isEmpty);
    },
  );

  test(
    'disable drains in-flight token rotation and unregisters both tokens',
    () async {
      final platform = DevicePlatform();
      final repository = DeviceRepository();
      final service = PushService(
        repository,
        MemorySecureStorage()..userId = 'alice',
        'alice',
        (_) {},
        platform: platform,
      );
      addTearDown(service.dispose);
      addTearDown(platform.close);
      await service.enable();
      repository.gate = Completer<void>();
      repository.blockedToken = 'new-token';
      platform.refreshed.add('new-token');
      await Future<void>.delayed(Duration.zero);
      final disable = service.disable();
      repository.gate!.complete();
      await disable;
      expect(repository.devices, isEmpty);
      expect(platform.tokenPresent, false);
    },
  );

  test(
    'a disposed older activation cannot unregister the new active registration',
    () async {
      final devices = <String>{};
      final oldPlatform = DevicePlatform();
      final newPlatform = DevicePlatform();
      final oldRepo = DeviceRepository(devices: devices)
        ..gate = Completer<void>();
      final storage = MemorySecureStorage()..userId = 'alice';
      final old = PushService(
        oldRepo,
        storage,
        'alice',
        (_) {},
        platform: oldPlatform,
      );
      final pending = old.enable();
      await Future<void>.delayed(Duration.zero);
      old.dispose();
      final current = PushService(
        DeviceRepository(devices: devices),
        storage,
        'alice',
        (_) {},
        platform: newPlatform,
      );
      addTearDown(current.dispose);
      addTearDown(oldPlatform.close);
      addTearDown(newPlatform.close);
      await current.enable();
      oldRepo.gate!.complete();
      await pending;
      expect(devices, {'device-token'});
      expect(current.state.valueOrNull, true);
    },
  );

  test(
    'Dedicated Cloud credentials never enter public ARIA request headers',
    () async {
      final repository = AriaRepository(
        apiKey: 'dedicated-secret',
        wandbBaseUrl: 'https://dedicated.example',
      );
      addTearDown(repository.dispose);
      try {
        await repository.threads();
        fail('Expected the server mismatch to be rejected');
      } on DioException catch (error) {
        expect(error.error, isA<UnsupportedError>());
        expect(
          error.requestOptions.headers.containsKey('Authorization'),
          false,
        );
      }
    },
  );

  test(
    'relay host binding blocks credentials from another W&B installation',
    () async {
      final repository = NotificationsRepository(
        apiKey: 'dedicated-secret',
        baseUrl: 'https://push.example',
        wandbBaseUrl: 'https://dedicated.example',
      );
      addTearDown(repository.dispose);
      try {
        await repository.rules();
        fail('Expected the server mismatch to be rejected');
      } on DioException catch (error) {
        expect(error.error, isA<UnsupportedError>());
        expect(
          error.requestOptions.headers.containsKey('Authorization'),
          false,
        );
      }
    },
  );
}
