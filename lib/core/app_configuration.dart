class AppConfiguration {
  AppConfiguration._();

  static const pushRelayUrl = String.fromEnvironment('PUSH_RELAY_URL');
  static const pushWandbBaseUrl = String.fromEnvironment(
    'PUSH_WANDB_BASE_URL',
    defaultValue: 'https://api.wandb.ai',
  );
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );

  static bool get pushConfigured =>
      pushRelayUrl.isNotEmpty &&
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;
}

bool sameSecureOrigin(String first, String second) {
  final a = Uri.tryParse(first);
  final b = Uri.tryParse(second);
  return a != null &&
      b != null &&
      a.scheme == 'https' &&
      b.scheme == 'https' &&
      a.host.isNotEmpty &&
      b.host.isNotEmpty &&
      a.userInfo.isEmpty &&
      b.userInfo.isEmpty &&
      a.origin == b.origin;
}
