import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../storage/local_cache.dart';
import '../storage/secure_storage.dart';

class SseEvent {
  const SseEvent({required this.event, required this.data});
  final String event;
  final Map<String, dynamic> data;
}

class ApiClient {
  ApiClient({
    required SecureStorageService secureStorage,
    required LocalCacheService cache,
  })  : _secureStorage = secureStorage,
        _cache = cache {
    _dio = Dio(
      BaseOptions(
        baseUrl: effectiveBaseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.baseUrl = effectiveBaseUrl;
          final token = await _secureStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final SecureStorageService _secureStorage;
  final LocalCacheService _cache;
  late final Dio _dio;

  String get effectiveBaseUrl {
    final custom = _cache.getCustomApiBaseUrl();
    if (custom != null && custom.isNotEmpty) return custom;
    return AppConfig.apiBaseUrl;
  }

  Dio get dio => _dio;

  /// Mengirim pesan ke endpoint SSE `POST /api/chat/stream` dan mem-parsing
  /// event `delta`, `tool`, `done`, dan `error` secara real-time.
  Stream<SseEvent> streamChat({
    required String message,
    String? moodTag,
  }) async* {
    final token = await _secureStorage.getToken();
    final client = http.Client();

    try {
      final request = http.Request(
        'POST',
        Uri.parse('$effectiveBaseUrl/api/chat/stream'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'text/event-stream';
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.body = jsonEncode({
        'message': message,
        if (moodTag != null) 'moodTag': moodTag,
      });

      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(seconds: 45));

      if (streamedResponse.statusCode != 200) {
        final bodyText = await streamedResponse.stream.bytesToString();
        throw Exception(
          'Server mengembalikan status ${streamedResponse.statusCode}: $bodyText',
        );
      }

      String currentEvent = 'message';
      final dataBuffer = StringBuffer();

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('event:')) {
          currentEvent = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          dataBuffer.write(line.substring(5).trim());
        } else if (line.isEmpty && dataBuffer.isNotEmpty) {
          final rawJson = dataBuffer.toString();
          dataBuffer.clear();
          try {
            final parsed = jsonDecode(rawJson) as Map<String, dynamic>;
            yield SseEvent(event: currentEvent, data: parsed);
          } catch (_) {
            // Abaikan potongan frame tak lengkap
          }
          currentEvent = 'message';
        }
      }
    } finally {
      client.close();
    }
  }
}
