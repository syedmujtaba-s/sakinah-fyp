import 'package:dio/dio.dart';
import '../config/api_config.dart';

class DailyWisdomService {
  static final String _baseUrl = ApiConfig.baseUrl;

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
  ));

  /// GET /api/daily-wisdom
  /// Returns: { lesson, story_title, story_period, summary }
  /// Falls back to local Seerah wisdom if backend is unreachable.
  static Future<Map<String, dynamic>> getDailyWisdom() async {
    try {
      final response = await _dio.get('/api/daily-wisdom');
      return Map<String, dynamic>.from(response.data);
    } catch (_) {
      return _fallbackWisdom();
    }
  }

  static Map<String, dynamic> _fallbackWisdom() {
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays + 1;
    const fallbacks = [
      {
        'lesson': 'Even in the cave, the Prophet (PBUH) said: Do not grieve, indeed Allah is with us.',
        'story_title': 'The Cave of Thawr',
        'story_period': '13th Year of Prophethood',
      },
      {
        'lesson': 'After the Year of Sorrow, came the Night Journey — divine gifts follow human losses.',
        'story_title': 'The Night Journey (Isra and Mi\'raj)',
        'story_period': '11th Year of Prophethood',
      },
      {
        'lesson': 'The Prophet (PBUH) forgave at the height of his power — forgiveness is strength.',
        'story_title': 'Forgiveness at the Conquest of Makkah',
        'story_period': '8th Year After Hijrah',
      },
      {
        'lesson': 'Bilal endured the boulder repeating "Ahad" — inner conviction outlasts outer suffering.',
        'story_title': 'Bilal ibn Rabah\'s Perseverance',
        'story_period': 'Early Makkah Period',
      },
      {
        'lesson': 'Khadijah\'s words steadied the Prophet when he trembled — never underestimate sincere support.',
        'story_title': 'Khadijah\'s Unwavering Support',
        'story_period': 'Early Prophethood',
      },
    ];
    return Map<String, dynamic>.from(fallbacks[dayOfYear % fallbacks.length]);
  }
}
