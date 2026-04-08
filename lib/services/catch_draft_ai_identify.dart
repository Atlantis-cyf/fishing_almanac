import 'package:fishing_almanac/analytics/analytics_client.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/services/species_identification.dart';
import 'package:fishing_almanac/state/catch_draft.dart';

/// 对 [CatchDraft] 中的当前照片发起一次 AI 识别（若已有与 [CatchDraft.aiMediaSeq] 匹配的有效缓存则跳过）。
///
/// 结果写入 [CatchDraft] 并 [CatchDraft.signalListeners]，供选点页后台预取、编辑页直接展示。
Future<void> performCatchDraftIdentification({
  required CatchDraft draft,
  required SpeciesIdentificationService svc,
  required AnalyticsClient analytics,
}) async {
  final hasBytes = draft.imageBytes != null && draft.imageBytes!.isNotEmpty;
  final hasUrl = draft.imageUrlFallback != null && draft.imageUrlFallback!.isNotEmpty;
  if (!hasBytes && !hasUrl) return;

  if (draft.aiIdentifyValidForMediaSeq == draft.aiMediaSeq) return;
  if (draft.aiIdentifyInFlight) return;

  draft.aiIdentifyInFlight = true;
  draft.signalListeners();

  final seq = draft.aiMediaSeq;

  analytics.trackFireAndForget(
    'ai_identify_requested',
    properties: <String, dynamic>{
      'has_bytes': hasBytes,
      'has_url': hasUrl,
      'upload_flow_id': draft.activeUploadFlowId,
      'phase': 'prefetch_or_edit',
    },
  );

  try {
    final r = await svc.identifySpecies(
      imageBytes: draft.imageBytes,
      imageUrl: draft.imageUrlFallback,
    );
    if (draft.aiMediaSeq != seq) return;

    draft.aiIsFish = r.isFish;
    draft.aiSpeciesZh = r.speciesZh;
    draft.aiTaxonomyZh = r.taxonomyZh;
    draft.aiInCatalog = r.inCatalog;

    if (!r.isFish) {
      draft.aiCachedScientificName = null;
      draft.aiCachedConfidence = null;
      draft.aiCachedApiFailed = false;
      draft.aiIdentifyLastApiStatusCode = null;
      draft.aiIdentifyLastApiMessage = null;
      draft.aiPendingIdentifyFailureSnack = false;
      draft.aiIdentifyValidForMediaSeq = seq;
      draft.aiPendingNotFishDialog = true;
      analytics.trackFireAndForget(
        'ai_identify_not_fish',
        properties: <String, dynamic>{
          'upload_flow_id': draft.activeUploadFlowId,
        },
      );
      return;
    }

    draft.aiCachedScientificName = r.scientificName;
    draft.aiCachedConfidence = r.confidence;
    draft.aiCachedApiFailed = false;
    draft.aiIdentifyLastApiStatusCode = null;
    draft.aiIdentifyLastApiMessage = null;
    draft.aiPendingIdentifyFailureSnack = false;
    draft.aiPendingNotFishDialog = false;
    draft.aiIdentifyValidForMediaSeq = seq;

    final aiSuccess = r.scientificName.isNotEmpty && r.scientificName != '—';
    analytics.trackFireAndForget(
      'ai_identify_completed',
      properties: <String, dynamic>{
        'success': aiSuccess,
        'confidence': r.confidence,
        'in_catalog': r.inCatalog,
        'upload_flow_id': draft.activeUploadFlowId,
      },
    );
  } on ApiException catch (e) {
    if (draft.aiMediaSeq != seq) return;
    draft.aiIsFish = true;
    draft.aiSpeciesZh = null;
    draft.aiTaxonomyZh = null;
    draft.aiInCatalog = true;
    draft.aiCachedScientificName = null;
    draft.aiCachedConfidence = null;
    draft.aiCachedApiFailed = true;
    draft.aiIdentifyLastApiStatusCode = e.statusCode;
    draft.aiIdentifyLastApiMessage = e.message;
    draft.aiPendingIdentifyFailureSnack = true;
    draft.aiPendingNotFishDialog = false;
    draft.aiIdentifyValidForMediaSeq = seq;
    analytics.trackFireAndForget(
      'ai_identify_failed',
      properties: <String, dynamic>{
        'error_type': 'ApiException',
        'message_len': e.message.length,
        'upload_flow_id': draft.activeUploadFlowId,
      },
    );
  } catch (e) {
    if (draft.aiMediaSeq != seq) return;
    draft.aiIsFish = true;
    draft.aiSpeciesZh = null;
    draft.aiTaxonomyZh = null;
    draft.aiInCatalog = true;
    draft.aiCachedScientificName = null;
    draft.aiCachedConfidence = null;
    draft.aiCachedApiFailed = true;
    draft.aiIdentifyLastApiStatusCode = null;
    draft.aiIdentifyLastApiMessage = e.toString();
    draft.aiPendingIdentifyFailureSnack = true;
    draft.aiPendingNotFishDialog = false;
    draft.aiIdentifyValidForMediaSeq = seq;
    analytics.trackFireAndForget(
      'ai_identify_failed',
      properties: <String, dynamic>{
        'error_type': 'Exception',
        'upload_flow_id': draft.activeUploadFlowId,
      },
    );
  } finally {
    // 仅结束「本张照片」这一次请求；换图后 seq 已变，勿误清新一轮 inFlight。
    if (draft.aiMediaSeq == seq) {
      draft.aiIdentifyInFlight = false;
      draft.signalListeners();
    }
  }
}
