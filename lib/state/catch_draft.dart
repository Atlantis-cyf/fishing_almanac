import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:fishing_almanac/models/catch_review_status.dart';
import 'package:fishing_almanac/models/published_catch.dart';

class CatchDraft extends ChangeNotifier {
  Uint8List? imageBytes;
  String? imageUrlFallback;
  String scientificName = '';
  String notes = '';
  double weightKg = 0;
  double lengthCm = 0;
  String locationLabel = '太平洋港口终点站';
  double? lat = 34.0522;
  double? lng = -118.2437;
  String? editingPublishedId;

  /// 正在编辑的已发布条目的审核态（新建草稿为 [CatchReviewStatus.approved]）。
  CatchReviewStatus editingReviewStatus = CatchReviewStatus.approved;

  /// 当前“上传鱼获流程”的临时 id（用于埋点串联漏斗步骤）。
  /// 仅在打开编辑页时生成；发布成功/重置时清空。
  String? activeUploadFlowId;

  /// 编辑页在进入选点等子路由前缓存的 AI 识别态，返回后用于恢复展示。
  String? editCacheAiScientificName;
  double? editCacheAiConfidence;
  bool editCacheIdentifyFailed = false;

  /// AI 识别结果中的附加字段（用于新鱼种创建流程）。
  bool aiIsFish = true;
  String? aiSpeciesZh;
  String? aiTaxonomyZh;
  bool aiInCatalog = true;
  bool imageAuthorized = false;

  // --- AI 识别缓存（选点页预取 + 编辑页展示，按 [aiMediaSeq] 失效）---

  /// 换图自增；与 [aiIdentifyValidForMediaSeq] 一致时表示当前缓存有效。
  int aiMediaSeq = 0;

  bool aiIdentifyInFlight = false;

  /// 非空且等于 [aiMediaSeq] 时，[aiCachedScientificName] 等与当前照片对应。
  int? aiIdentifyValidForMediaSeq;

  String? aiCachedScientificName;
  double? aiCachedConfidence;
  bool aiCachedApiFailed = false;
  int? aiIdentifyLastApiStatusCode;
  String? aiIdentifyLastApiMessage;

  /// 编辑页消费后弹出「非鱼类」说明。
  bool aiPendingNotFishDialog = false;

  /// 编辑页消费后弹出识别失败 SnackBar（预取阶段不弹，避免打断选点）。
  bool aiPendingIdentifyFailureSnack = false;

  void _invalidateAiIdentifyCache() {
    aiIdentifyInFlight = false;
    aiIdentifyValidForMediaSeq = null;
    aiCachedScientificName = null;
    aiCachedConfidence = null;
    aiCachedApiFailed = false;
    aiIdentifyLastApiStatusCode = null;
    aiIdentifyLastApiMessage = null;
    aiPendingNotFishDialog = false;
    aiPendingIdentifyFailureSnack = false;
  }

  bool get hasValidAiIdentifyCache =>
      aiIdentifyValidForMediaSeq != null && aiIdentifyValidForMediaSeq == aiMediaSeq;

  /// 供 [performCatchDraftIdentification] 等在类外触发重建（避免外部调用受保护的 [notifyListeners]）。
  void signalListeners() => notifyListeners();

  void setPickedImageBytes(List<int> bytes) {
    imageBytes = Uint8List.fromList(bytes);
    imageUrlFallback = null;
    aiMediaSeq++;
    _invalidateAiIdentifyCache();
    notifyListeners();
  }

  /// 用户更换照片后重置与 AI/鱼种相关的草稿，避免沿用上一张图的元数据。
  void resetAiMetaForNewImage() {
    aiIsFish = true;
    aiSpeciesZh = null;
    aiTaxonomyZh = null;
    aiInCatalog = true;
    imageAuthorized = false;
    scientificName = '';
    notifyListeners();
  }

  void setLocationFromGps(double la, double lo, String label) {
    lat = la;
    lng = lo;
    locationLabel = label;
    notifyListeners();
  }

  void setLocationFuzzy(String label) {
    lat = null;
    lng = null;
    locationLabel = label.isEmpty ? '模糊位置' : label;
    notifyListeners();
  }

  /// 编辑页在进入选点前写入表单与 AI 缓存（避免外部直接调用 [notifyListeners]）。
  void applyEditScreenPersistSnapshot({
    required String scientificName,
    required String notes,
    required double weightKg,
    required double lengthCm,
    String? editCacheAiScientificName,
    double? editCacheAiConfidence,
    required bool editCacheIdentifyFailed,
  }) {
    this.scientificName = scientificName;
    this.notes = notes;
    this.weightKg = weightKg;
    this.lengthCm = lengthCm;
    this.editCacheAiScientificName = editCacheAiScientificName;
    this.editCacheAiConfidence = editCacheAiConfidence;
    this.editCacheIdentifyFailed = editCacheIdentifyFailed;
    notifyListeners();
  }

  void updateEditAiCacheOnly({
    String? editCacheAiScientificName,
    double? editCacheAiConfidence,
    required bool editCacheIdentifyFailed,
  }) {
    this.editCacheAiScientificName = editCacheAiScientificName;
    this.editCacheAiConfidence = editCacheAiConfidence;
    this.editCacheIdentifyFailed = editCacheIdentifyFailed;
    notifyListeners();
  }

  void skipLocation() {
    lat = null;
    lng = null;
    locationLabel = '未标注位置';
    notifyListeners();
  }

  void clearForNewRecord() {
    imageBytes = null;
    imageUrlFallback = null;
    scientificName = '';
    notes = '';
    weightKg = 0;
    lengthCm = 0;
    locationLabel = '太平洋港口终点站';
    lat = 34.0522;
    lng = -118.2437;
    editingPublishedId = null;
    editingReviewStatus = CatchReviewStatus.approved;
    activeUploadFlowId = null;
    editCacheAiScientificName = null;
    editCacheAiConfidence = null;
    editCacheIdentifyFailed = false;
    aiIsFish = true;
    aiSpeciesZh = null;
    aiTaxonomyZh = null;
    aiInCatalog = true;
    imageAuthorized = false;
    aiMediaSeq = 0;
    _invalidateAiIdentifyCache();
    notifyListeners();
  }

  void loadFromPublished(PublishedCatch p) {
    editingPublishedId = p.id;
    editingReviewStatus = p.reviewStatus;
    imageUrlFallback = p.imageUrlFallback;
    imageBytes = p.imageBase64 != null && p.imageBase64!.isNotEmpty
        ? Uint8List.fromList(base64Decode(p.imageBase64!))
        : null;
    scientificName = p.scientificName;
    notes = p.notes;
    weightKg = p.weightKg;
    lengthCm = p.lengthCm;
    locationLabel = p.locationLabel;
    lat = p.lat;
    lng = p.lng;
    aiMediaSeq++;
    _invalidateAiIdentifyCache();
    notifyListeners();
  }

  /// 新建或覆盖已发布条目（保留原 `id` 与 `occurredAt` 当 [original] 非空）。
  PublishedCatch buildPublishedForSave({PublishedCatch? original}) {
    final id = original?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final at = original?.occurredAt ?? DateTime.now();
    String? b64;
    if (imageBytes != null && imageBytes!.isNotEmpty) {
      b64 = base64Encode(imageBytes!);
    } else {
      b64 = original?.imageBase64;
    }
    final CatchReviewStatus outReview;
    if (original == null) {
      outReview = CatchReviewStatus.approved;
    } else if (original.reviewStatus == CatchReviewStatus.rejected) {
      outReview = CatchReviewStatus.pendingReview;
    } else {
      outReview = original.reviewStatus;
    }
    return PublishedCatch(
      id: id,
      imageBase64: b64,
      imageUrlFallback: imageUrlFallback ?? original?.imageUrlFallback,
      scientificName: scientificName,
      notes: notes,
      weightKg: weightKg,
      lengthCm: lengthCm,
      locationLabel: locationLabel,
      lat: lat,
      lng: lng,
      occurredAt: at,
      reviewStatus: outReview,
    );
  }
}
