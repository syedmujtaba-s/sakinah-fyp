import 'package:dio/dio.dart';
import '../config/api_config.dart';

class GuidanceService {
  static final String _baseUrl = ApiConfig.baseUrl;

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 90),
    headers: {'Content-Type': 'application/json'},
  ));

  /// Calls POST /api/guidance with journal entry and emotion.
  /// Retries once on receive-timeout — the backend's first call warms the
  /// embedder + Groq cache, the second usually returns in seconds.
  ///
  /// [excludeStoryIds] — story IDs the user has already tried whose advice
  /// didn't help. The backend filters these out before retrieval so a
  /// different story surfaces (used by the "need alternative" feedback flow).
  ///
  /// [followupQuestion] + [previousStoryId] — when set, the backend skips
  /// a fresh RAG lookup and continues the same story-grounded conversation.
  /// [previousSeerahConnection] feeds the LLM the earlier narrative so the
  /// follow-up answer goes deeper instead of repeating.
  static Future<Map<String, dynamic>> getGuidance({
    required String journalEntry,
    required String emotion,
    List<String> excludeStoryIds = const [],
    String? followupQuestion,
    String? previousStoryId,
    String? previousSeerahConnection,
  }) async {
    final payload = {
      'journal_entry': journalEntry,
      'emotion': emotion.toLowerCase(),
      if (excludeStoryIds.isNotEmpty) 'exclude_story_ids': excludeStoryIds,
      if (followupQuestion != null && followupQuestion.isNotEmpty)
        'followup_question': followupQuestion,
      if (previousStoryId != null && previousStoryId.isNotEmpty)
        'previous_story_id': previousStoryId,
      if (previousSeerahConnection != null && previousSeerahConnection.isNotEmpty)
        'previous_seerah_connection': previousSeerahConnection,
    };

    try {
      final response = await _dio.post('/api/guidance', data: payload);
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        final retry = await _dio.post('/api/guidance', data: payload);
        return Map<String, dynamic>.from(retry.data);
      }
      rethrow;
    }
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
