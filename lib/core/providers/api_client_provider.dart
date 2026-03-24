import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/secure_storage_service.dart';

/// Provides the secure storage service.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
