import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';

class OAuthResult {
  const OAuthResult({
    required this.success,
    required this.provider,
    this.email,
    this.errorMessage,
  });

  final bool success;
  final String provider;
  final String? email;
  final String? errorMessage;
}

/// Menangani alur login OAuth 2.0 yang aman melalui backend + custom deep link
/// (`temanhari://auth-callback`) untuk Google Calendar dan Microsoft Outlook.
class OAuthService {
  OAuthService(this._apiClient);

  final ApiClient _apiClient;

  Future<OAuthResult> connectProvider(String provider) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/calendar/$provider/auth-url',
        queryParameters: {'redirectScheme': AppConfig.oauthDeepLink},
      );

      final authUrl = response.data?['url'] as String?;
      if (authUrl == null || authUrl.isEmpty) {
        return OAuthResult(
          success: false,
          provider: provider,
          errorMessage: 'URL otorisasi tidak tersedia dari server.',
        );
      }

      final callbackUrl = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: AppConfig.oauthCallbackScheme,
      );

      final uri = Uri.parse(callbackUrl);
      final status = uri.queryParameters['status'];
      final email = uri.queryParameters['email'];
      final message = uri.queryParameters['message'];

      if (status == 'success') {
        return OAuthResult(
          success: true,
          provider: provider,
          email: email,
        );
      }
      return OAuthResult(
        success: false,
        provider: provider,
        errorMessage: message ?? 'Otorisasi dibatalkan atau gagal.',
      );
    } catch (e) {
      return OAuthResult(
        success: false,
        provider: provider,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> disconnectProvider(String provider) async {
    await _apiClient.dio.delete('/api/calendar/$provider/disconnect');
  }
}
