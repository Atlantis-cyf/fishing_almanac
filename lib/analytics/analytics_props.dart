/// Centralized analytics property keys and common values.
class AnalyticsProps {
  const AnalyticsProps._();

  // Common fields.
  static const String timestamp = 'timestamp';
  static const String platform = 'platform';
  static const String appVersion = 'app_version';
  static const String userId = 'user_id';
  static const String deviceId = 'device_id';

  // Generic identifiers.
  static const String requestId = 'request_id';
  static const String imageId = 'image_id';
  static const String speciesId = 'species_id';
  static const String speciesName = 'species_name';

  // Upload flow.
  static const String entryPosition = 'entry_position';
  static const String source = 'source';
  static const String uploadDurationMs = 'upload_duration_ms';
  static const String fileSize = 'file_size';

  // AI identify.
  static const String confidence = 'confidence';
  static const String latencyMs = 'latency_ms';
  static const String isSuccess = 'is_success';
  static const String errorCode = 'error_code';
  static const String errorMessage = 'error_message';

  // Encyclopedia.
  static const String unlockedSpeciesCount = 'unlocked_species_count';
  static const String totalSpeciesCount = 'total_species_count';
  static const String completionRate = 'completion_rate';
  static const String unlocked = 'unlocked';
  static const String isFirstTime = 'is_first_time';
  static const String unlockSource = 'unlock_source';

  // Feedback.
  static const String isCorrect = 'is_correct';

  // Common enum-like values.
  static const String sourceCamera = 'camera';
  static const String sourceAlbum = 'album';
  static const String unlockSourceAiIdentify = 'ai_identify';
}
