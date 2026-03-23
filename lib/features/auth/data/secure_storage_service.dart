import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _apiKeyKey = 'wandb_api_key';
  static const _entityKey = 'wandb_entity';
  static const _baseUrlKey = 'wandb_base_url';

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

  Future<void> clearAll() => _storage.deleteAll();
}
