import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../config/api_config.dart';

/// Multi-modal emotion detection client.
///
/// Calls POST /api/emotion/detect on the backend. Either or both of the
/// inputs (image, journal text) can be supplied — the backend fuses
/// whichever signals it receives and maps to Sakinah's 15-emotion taxonomy.
class FaceEmotionService {
  static final String _baseUrl = ApiConfig.baseUrl;

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Run multi-modal emotion detection.
  ///
  /// At least one of [imageBytes] (JPEG/PNG, recommended ≤ 100KB after
  /// client-side compression) or [journalText] must be supplied.
  ///
  /// Returns an [EmotionDetectionResult] with the predicted Sakinah-15
  /// emotion + confidence + per-modality breakdown.
  static Future<EmotionDetectionResult> detect({
    Uint8List? imageBytes,
    String? journalText,
  }) async {
    if ((imageBytes == null || imageBytes.isEmpty) &&
        (journalText == null || journalText.trim().isEmpty)) {
      throw ArgumentError('Provide at least one of imageBytes or journalText.');
    }

    final form = FormData();
    if (imageBytes != null && imageBytes.isNotEmpty) {
      // Compress before upload — typical phone JPEG is 90-200KB; we shrink to
      // ~30-50KB. Saves bandwidth, keeps enough pixels for the backend's
      // Haar cascade to find the face. The HSEmotion model itself takes
      // 224x224 input so we resize to 480px on the long side as a balanced
      // middle ground (plenty for detection, much smaller than the original).
      final compressed = await compute(_compressForUpload, imageBytes);
      form.files.add(MapEntry(
        'image',
        MultipartFile.fromBytes(compressed, filename: 'face.jpg'),
      ));
    }
    if (journalText != null && journalText.trim().isNotEmpty) {
      form.fields.add(MapEntry('journal_text', journalText));
    }

    debugPrint('[FaceEmotion] POST $_baseUrl/api/emotion/detect '
        '(image=${imageBytes?.length ?? 0}B, text="${journalText ?? ''}")');
    try {
      final response = await _dio.post('/api/emotion/detect', data: form);
      // Print the full payload so we can diagnose what the model actually saw.
      final data = response.data is Map ? response.data : <String, dynamic>{};
      debugPrint('[FaceEmotion] HTTP ${response.statusCode}\n'
          '  predicted: ${data['predicted_emotion']} (${data['confidence']})\n'
          '  face_raw:  ${data['face_predicted']} (${data['face_confidence']})\n'
          '  text_raw:  ${data['text_predicted']} (${data['text_confidence']})\n'
          '  sources:   ${data['sources_used']}\n'
          '  strategy:  ${data['fusion_strategy']}\n'
          '  face_err:  ${data['face_error']}');
      return EmotionDetectionResult.fromJson(
        Map<String, dynamic>.from(response.data),
      );
    } on DioException catch (e) {
      debugPrint('[FaceEmotion] DioException type=${e.type} '
          'status=${e.response?.statusCode} '
          'msg=${e.message} '
          'body=${e.response?.data}');
      rethrow;
    }
  }

  /// Lightweight ping that does NOT trigger model loads.
  static Future<bool> healthCheck() async {
    try {
      final r = await _dio.get('/api/emotion/health');
      return r.data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }
}

/// Top-level so it can run on a background isolate via `compute()`.
///
/// Decodes the original JPEG, downscales the longer edge to 480px, and
/// re-encodes at JPEG quality 85. 480px is a deliberate balance: small
/// enough to halve the upload (90KB → ~30-40KB on a typical phone) yet
/// large enough that the backend's Haar cascade still finds faces
/// reliably. (HSEmotion itself takes 224×224, so any extra resolution
/// past detection is discarded server-side.)
Uint8List _compressForUpload(Uint8List original) {
  final decoded = img.decodeImage(original);
  if (decoded == null) {
    // Decode failed — let the original bytes go through. The backend
    // will return a clean error rather than a corrupted upload.
    return original;
  }

  const targetLong = 480;
  img.Image resized = decoded;
  final longEdge = decoded.width >= decoded.height ? decoded.width : decoded.height;
  if (longEdge > targetLong) {
    resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? targetLong : null,
      height: decoded.height > decoded.width ? targetLong : null,
      interpolation: img.Interpolation.linear,
    );
  }

  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}

/// Strongly-typed response for the /api/emotion/detect endpoint.
///
/// Field names match the backend's [EmotionDetectionResponse] Pydantic model.
class EmotionDetectionResult {
  final String predictedEmotion;          // one of Sakinah's 15
  final double confidence;
  final Map<String, double> scores;       // 15-way distribution
  final List<String> sourcesUsed;         // ["face"], ["text"], or both
  final String fusionStrategy;
  final bool lowConfidence;
  final String? facePredicted;            // raw AffectNet label, e.g. "Happiness"
  final double faceConfidence;
  final double? valence;
  final double? arousal;
  final String? textPredicted;            // raw RoBERTa label, e.g. "joy"
  final double textConfidence;
  final bool textTranslated;
  final String? faceError;                // present when image was sent but face wasn't detected
  final String? faceErrorDetail;

  EmotionDetectionResult({
    required this.predictedEmotion,
    required this.confidence,
    required this.scores,
    required this.sourcesUsed,
    required this.fusionStrategy,
    required this.lowConfidence,
    this.facePredicted,
    this.faceConfidence = 0.0,
    this.valence,
    this.arousal,
    this.textPredicted,
    this.textConfidence = 0.0,
    this.textTranslated = false,
    this.faceError,
    this.faceErrorDetail,
  });

  factory EmotionDetectionResult.fromJson(Map<String, dynamic> json) {
    final rawScores = json['scores'] as Map<String, dynamic>? ?? {};
    return EmotionDetectionResult(
      predictedEmotion: (json['predicted_emotion'] ?? 'confused') as String,
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      scores: rawScores.map((k, v) => MapEntry(k, (v as num).toDouble())),
      sourcesUsed: List<String>.from(json['sources_used'] ?? const []),
      fusionStrategy: (json['fusion_strategy'] ?? 'none') as String,
      lowConfidence: (json['low_confidence'] ?? false) as bool,
      facePredicted: json['face_predicted'] as String?,
      faceConfidence: (json['face_confidence'] ?? 0.0).toDouble(),
      valence: (json['valence'] as num?)?.toDouble(),
      arousal: (json['arousal'] as num?)?.toDouble(),
      textPredicted: json['text_predicted'] as String?,
      textConfidence: (json['text_confidence'] ?? 0.0).toDouble(),
      textTranslated: (json['text_translated'] ?? false) as bool,
      faceError: json['face_error'] as String?,
      faceErrorDetail: json['face_error_detail'] as String?,
    );
  }

  /// True when the backend successfully analysed a face (vs. no-face fallback).
  bool get faceDetected => faceError == null && facePredicted != null;

  /// Capitalize first letter for display: "happy" -> "Happy".
  String get displayEmotion =>
      predictedEmotion.isEmpty
          ? 'Neutral'
          : predictedEmotion[0].toUpperCase() + predictedEmotion.substring(1);
}
