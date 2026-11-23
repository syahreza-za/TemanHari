import 'dart:io';

/// Konfigurasi runtime aplikasi TemanHari.
/// Bisa ditimpa saat menjalankan Flutter dengan:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:4000`
class AppConfig {
  static const String _definedBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get apiBaseUrl {
    if (_definedBaseUrl.isNotEmpty) {
      return _definedBaseUrl;
    }
    // Emulator Android menggunakan 10.0.2.2 untuk mengakses localhost komputer host.
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:4000';
    }
    return 'http://localhost:4000';
  }

  static const String oauthCallbackScheme = 'temanhari';
  static const String oauthDeepLink = 'temanhari://auth-callback';
}
