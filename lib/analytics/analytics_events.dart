/// Centralized analytics event names.
///
/// Keep event names in lower_snake_case for stable downstream analysis.
class AnalyticsEvents {
  const AnalyticsEvents._();

  static const String appLaunch = 'app_launch';
  static const String homeView = 'home_view';
  static const String uploadClick = 'upload_click';
  static const String uploadSuccess = 'upload_success';
  static const String aiIdentifyStart = 'ai_identify_start';
  static const String aiIdentifyResult = 'ai_identify_result';
  static const String aiIdentifyFail = 'ai_identify_fail';
  static const String speciesUnlock = 'species_unlock';
  static const String collectionView = 'collection_view';
  static const String speciesDetailView = 'species_detail_view';
  static const String identifyFeedback = 'identify_feedback';
}
