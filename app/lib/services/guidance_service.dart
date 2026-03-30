import 'package:dio/dio.dart';
import '../config/api_config.dart';

class GuidanceService {
  static final String _baseUrl = ApiConfig.baseUrl;

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  /// Calls POST /api/guidance with journal entry and emotion.
  /// Returns the AI-generated guidance response map.
  static Future<Map<String, dynamic>> getGuidance({
    required String journalEntry,
    required String emotion,
  }) async {
    final response = await _dio.post('/api/guidance', data: {
      'journal_entry': journalEntry,
      'emotion': emotion.toLowerCase(),
    });
    return Map<String, dynamic>.from(response.data);
  }

  /// Calls GET /api/emotions to get the list of supported emotions.
  static Future<List<String>> getEmotions() async {
    final response = await _dio.get('/api/emotions');
    final List<dynamic> emotions = response.data['emotions'];
    return emotions.cast<String>();
  }

  /// Calls GET /api/health to check if backend is running.
  static Future<bool> healthCheck() async {
    try {
      final response = await _dio.get('/api/health');
      return response.data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }
}
