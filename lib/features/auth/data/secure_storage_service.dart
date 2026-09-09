import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _apiKeyKey = 'wandb_api_key';
  static const _entityKey = 'wandb_entity';
  static const _baseUrlKey = 'wandb_base_url';
  static const _userIdKey = 'wandb_user_id';
  static const _pushEnabledKey = 'wandb_push_enabled';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> getApiKey() => _storage.read(key: _apiKeyKey);
  Future<void> setApiKey(String key) =>
      _storage.write(key: _apiKeyKey, value: key);
  Future<void> deleteApiKey() => _storage.delete(key: _apiKeyKey);

  Future<String?> getEntity() => _storage.read(key: _entityKey);
  Future<void> setEntity(String entity) =>
      _storage.write(key: _entityKey, value: entity);

  Future<String?> getBaseUrl() => _storage.read(key: _baseUrlKey);
  Future<void> setBaseUrl(String url) =>
      _storage.write(key: _baseUrlKey, value: url);
  Future<void> deleteBaseUrl() => _storage.delete(key: _baseUrlKey);

  Future<String?> getUserId() => _storage.read(key: _userIdKey);
  Future<void> setUserId(String id) =>
      _storage.write(key: _userIdKey, value: id);
  Future<bool> getPushEnabled({String? userId}) async {
    final id = userId ?? await getUserId();
    return id != null &&
        await _storage.read(key: '$_pushEnabledKey:$id') == 'true';
  }

  Future<void> setPushEnabled(bool value, {String? userId}) async {
    final id = userId ?? await getUserId();
    if (id != null)
      await _storage.write(
        key: '$_pushEnabledKey:$id',
        value: value.toString(),
      );
  }

  Future<void> clearAll() => _storage.deleteAll();
}
