import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Layanan Mode Suara Native (Bahasa Indonesia `id-ID`):
/// - Input suara pengguna via `speech_to_text`
/// - Balasan suara hangat AI via `flutter_tts`
class VoiceService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechReady = false;
  bool _ttsReady = false;
  bool _isListening = false;

  bool get isListening => _isListening;

  Future<void> initTts({double speechRate = 0.48}) async {
    if (_ttsReady) {
      await _tts.setSpeechRate(speechRate);
      return;
    }
    try {
      await _tts.setLanguage('id-ID');
      await _tts.setSpeechRate(speechRate);
      await _tts.setPitch(1.03);
      await _tts.setVolume(1.0);
      _ttsReady = true;
    } catch (e) {
      debugPrint('[TTS] Gagal inisialisasi flutter_tts: $e');
    }
  }

  Future<void> speak(String text, {double speechRate = 0.48}) async {
    final clean = text
        .replaceAll(RegExp(r'[*_`#]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return;

    await initTts(speechRate: speechRate);
    await _tts.stop();
    await _tts.speak(clean);
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<bool> startListening({
    required void Function(String recognizedText, bool isFinal) onResult,
    required void Function(String status) onStatus,
  }) async {
    await stopSpeaking();

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
          onStatus(status);
        },
        onError: (err) {
          _isListening = false;
          onStatus('error:${err.errorMsg}');
        },
      );
    }

    if (!_speechReady) return false;

    _isListening = true;
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'id_ID',
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
        if (result.finalResult) {
          _isListening = false;
        }
      },
    );
    return true;
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _speech.stop();
  }
}
