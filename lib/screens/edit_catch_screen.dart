import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/analytics/analytics_client.dart';
import 'package:fishing_almanac/analytics/analytics_events.dart';
import 'package:fishing_almanac/analytics/analytics_props.dart';
import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/repositories/catch_repository.dart';
import 'package:fishing_almanac/repositories/persistence_exception.dart';
import 'package:fishing_almanac/services/catch_draft_ai_identify.dart';
import 'package:fishing_almanac/services/species_identification.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';
import 'package:fishing_almanac/models/published_catch.dart';
import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/router/app_router.dart';
import 'package:fishing_almanac/state/catch_draft.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/catch_ui_constants.dart';
import 'package:fishing_almanac/widgets/catch_image_display.dart';
import 'package:fishing_almanac/widgets/species_catalog_search_field.dart';
import 'package:fishing_almanac/theme/app_font.dart';

class EditCatchScreen extends StatefulWidget {
  const EditCatchScreen({super.key, this.editingPublishedId});

  final String? editingPublishedId;

  @override
  State<EditCatchScreen> createState() => _EditCatchScreenState();
}

class _EditCatchScreenState extends State<EditCatchScreen> {
  final _speciesController = TextEditingController();
  final _speciesFocusNode = FocusNode();
  final _notesController = TextEditingController();
  final _weightController = TextEditingController();
  final _lengthController = TextEditingController();
  bool _synced = false;

  bool _aiLoading = false;
  bool _identifyFailed = false;
  String? _aiScientificName;
  double? _aiConfidence;
  CatchDraft? _draftListenTarget;
  bool _draftListenAttached = false;
  /// 防止连点触发两次发布逻辑（不驱动 UI 阻塞）。
  bool _publishBusy = false;
  String _latestUploadSource = 'unknown';

  Timer? _manualSpeciesDebounce;
  bool _programmaticSpeciesUpdate = false;
  String? _lastReportedManualSpeciesValue;
  int _manualSpeciesInputCount = 0;

  void _onSpeciesControllerChanged() {
    if (_programmaticSpeciesUpdate) return;
    final v = _speciesController.text.trim();
    if (v.isEmpty) return;

    _manualSpeciesDebounce?.cancel();
    _manualSpeciesDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final vv = _speciesController.text.trim();
      if (vv.isEmpty) return;
      if (_lastReportedManualSpeciesValue == vv) return;
      _manualSpeciesInputCount++;
      _lastReportedManualSpeciesValue = vv;
    });
  }

  @override
  void initState() {
    super.initState();
    _speciesController.addListener(_onSpeciesControllerChanged);
  }

  @override
  void dispose() {
    if (_draftListenAttached && _draftListenTarget != null) {
      _draftListenTarget!.removeListener(_onCatchDraftChanged);
    }
    _manualSpeciesDebounce?.cancel();
    _speciesFocusNode.dispose();
    _speciesController.dispose();
    _notesController.dispose();
    _weightController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  static String _metricTextForDraft(double v) {
    if (v <= 0) return '';
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toString();
  }

  // Publish does not require metrics; empty or invalid input is treated as 0.
  static double _metricOrZero(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    final v = double.tryParse(t);
    if (v == null || v < 0) return 0;
    return v;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_draftListenAttached) {
      _draftListenAttached = true;
      _draftListenTarget = context.read<CatchDraft>();
      _draftListenTarget!.addListener(_onCatchDraftChanged);
    }
    if (_synced) return;
    _synced = true;
    final draft = context.read<CatchDraft>();
    final id = widget.editingPublishedId;
    final analytics = context.read<AnalyticsClient>();
    draft.activeUploadFlowId = 'flow_${DateTime.now().toUtc().millisecondsSinceEpoch}';
    if (id != null) {
      analytics.trackFireAndForget(
        AnalyticsEvents.uploadClick,
        properties: <String, dynamic>{AnalyticsProps.entryPosition: 'edit_catch_open_edit'},
      );
      scheduleMicrotask(() => _hydrateEditing(id));
    } else {
      final hasImage =
          (draft.imageBytes != null && draft.imageBytes!.isNotEmpty) || (draft.imageUrlFallback != null && draft.imageUrlFallback!.isNotEmpty);
      analytics.trackFireAndForget(
        AnalyticsEvents.uploadClick,
        properties: <String, dynamic>{AnalyticsProps.entryPosition: 'edit_catch_open_new'},
      );

      if (draft.scientificName.isNotEmpty) {
        _programmaticSpeciesUpdate = true;
        _speciesController.text = SpeciesCatalog.displayZhForScientific(draft.scientificName);
        _programmaticSpeciesUpdate = false;
      }
      _notesController.text = draft.notes;
      _weightController.text = _metricTextForDraft(draft.weightKg);
      _lengthController.text = _metricTextForDraft(draft.lengthCm);
      setState(() => _hydrateAiUiFromDraft(draft));
      _scheduleIdentify(draft);
    }
  }

  Future<void> _hydrateEditing(String id) async {
    final repo = context.read<CatchRepository>();
    final p = await repo.getById(id);
    if (!mounted) return;
    final draft = context.read<CatchDraft>();
    if (p != null) draft.loadFromPublished(p);
    final analytics = context.read<AnalyticsClient>();

    _programmaticSpeciesUpdate = true;
    _speciesController.text = SpeciesCatalog.displayZhForScientific(draft.scientificName);
    _programmaticSpeciesUpdate = false;
    _notesController.text = draft.notes;
    _weightController.text = _metricTextForDraft(draft.weightKg);
    _lengthController.text = _metricTextForDraft(draft.lengthCm);
    _aiScientificName = draft.scientificName;
    _aiConfidence = 0.98;
    _aiLoading = false;

    final hasImage =
        (draft.imageBytes != null && draft.imageBytes!.isNotEmpty) || (draft.imageUrlFallback != null && draft.imageUrlFallback!.isNotEmpty);
    if (hasImage && _latestUploadSource == 'unknown') _latestUploadSource = 'published';

    draft.updateEditAiCacheOnly(
      editCacheAiScientificName: _aiScientificName ?? draft.scientificName,
      editCacheAiConfidence: _aiConfidence,
      editCacheIdentifyFailed: _identifyFailed,
    );

    setState(() {});
  }

  /// 将当前表单与 AI 展示态写入 [CatchDraft]，再进入选点等子页面，避免返回后丢失。
  void _persistEditingToDraft(CatchDraft draft) {
    final manual = _speciesController.text.trim();
    final aiOk =
        _aiScientificName != null && _aiScientificName!.isNotEmpty && _aiScientificName != '—';
    final String species;
    if (manual.isNotEmpty) {
      species = manual;
    } else if (aiOk) {
      species = _aiScientificName!;
    } else {
      species = '未确定';
    }
    draft.applyEditScreenPersistSnapshot(
      scientificName: SpeciesCatalog.resolveScientificNameFromUserInput(species),
      notes: _notesController.text.trim(),
      weightKg: double.tryParse(_weightController.text.trim()) ?? 0,
      lengthCm: double.tryParse(_lengthController.text.trim()) ?? 0,
      editCacheAiScientificName: _aiScientificName,
      editCacheAiConfidence: _aiConfidence,
      editCacheIdentifyFailed: _identifyFailed,
    );
  }

  void _restoreEditingFromDraft(CatchDraft draft) {
    if (_speciesController.text != SpeciesCatalog.displayZhForScientific(draft.scientificName)) {
      _programmaticSpeciesUpdate = true;
      _speciesController.text = SpeciesCatalog.displayZhForScientific(draft.scientificName);
      _programmaticSpeciesUpdate = false;
    }
    if (_notesController.text != draft.notes) {
      _notesController.text = draft.notes;
    }
    _weightController.text = _metricTextForDraft(draft.weightKg);
    _lengthController.text = _metricTextForDraft(draft.lengthCm);
    setState(() {
      _aiScientificName = draft.editCacheAiScientificName;
      _aiConfidence = draft.editCacheAiConfidence;
      _identifyFailed = draft.editCacheIdentifyFailed;
    });
  }

  void _onCatchDraftChanged() {
    if (!mounted || widget.editingPublishedId != null) return;
    final d = _draftListenTarget;
    if (d == null) return;
    setState(() => _hydrateAiUiFromDraft(d));
    _drainDraftIdentifyUiFlags(d);
  }

  /// 从 [CatchDraft] 的预取/识别缓存同步顶栏 AI 展示与鱼种输入框。
  void _hydrateAiUiFromDraft(CatchDraft d) {
    if (widget.editingPublishedId != null) return;
    _aiLoading = d.aiIdentifyInFlight;
    if (d.hasValidAiIdentifyCache) {
      if (d.aiCachedApiFailed) {
        _identifyFailed = true;
        _aiScientificName = null;
        _aiConfidence = null;
      } else if (!d.aiIsFish) {
        _identifyFailed = true;
        _aiScientificName = null;
        _aiConfidence = null;
      } else {
        _identifyFailed = false;
        _aiScientificName = d.aiCachedScientificName;
        _aiConfidence = d.aiCachedConfidence;
        if (_speciesController.text.trim().isEmpty &&
            d.aiCachedScientificName != null &&
            d.aiCachedScientificName!.isNotEmpty &&
            d.aiCachedScientificName != '—') {
          _programmaticSpeciesUpdate = true;
          final displayName = d.aiSpeciesZh?.isNotEmpty == true
              ? d.aiSpeciesZh!
              : SpeciesCatalog.displayZhForScientific(d.aiCachedScientificName!);
          _speciesController.text = displayName;
          _programmaticSpeciesUpdate = false;
        }
      }
    } else if (!d.aiIdentifyInFlight) {
      _aiScientificName = null;
      _aiConfidence = null;
      _identifyFailed = false;
    }
  }

  void _drainDraftIdentifyUiFlags(CatchDraft d) {
    if (!mounted || widget.editingPublishedId != null) return;
    if (d.aiPendingNotFishDialog) {
      d.aiPendingNotFishDialog = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNotFishDialog();
      });
    }
    if (d.aiPendingIdentifyFailureSnack) {
      d.aiPendingIdentifyFailureSnack = false;
      final code = d.aiIdentifyLastApiStatusCode;
      final msg = d.aiIdentifyLastApiMessage ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showIdentifyFailure(ApiException(message: msg, statusCode: code));
      });
    }
  }

  void _scheduleIdentify(CatchDraft draft) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final d = context.read<CatchDraft>();
      await _runIdentification(d);
    });
  }

  /// 用户更换照片后清空 AI/鱼种草稿，避免仍用上一张图的识别结果发布。
  void _resetSpeciesStateForNewImage(CatchDraft draft) {
    draft.resetAiMetaForNewImage();
    _programmaticSpeciesUpdate = true;
    _speciesController.clear();
    _programmaticSpeciesUpdate = false;
    setState(() {
      _aiScientificName = null;
      _aiConfidence = null;
      _identifyFailed = false;
    });
  }

  Future<void> _runIdentification(CatchDraft draft) async {
    await performCatchDraftIdentification(
      draft: draft,
      svc: context.read<SpeciesIdentificationService>(),
      analytics: context.read<AnalyticsClient>(),
    );
    if (!mounted) return;
    setState(() => _hydrateAiUiFromDraft(draft));
    _drainDraftIdentifyUiFlags(draft);
  }

  void _showIdentifyFailure(ApiException e) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    final raw = (e.message).toLowerCase();
    final notConfigured = e.statusCode == 503 &&
        (raw.contains('未配置') ||
            raw.contains('not configured') ||
            raw.contains('missing') ||
            raw.contains('doubao'));
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          notConfigured
              ? '识别服务未配置（缺少豆包 API Key），请联系管理员配置后重试。'
              : '识别失败，请手动填写\n${e.message}',
          style: const TextStyle(height: 1.35),
        ),
      ),
    );
  }

  void _showNotFishDialog() {
    if (!mounted) return;
    final draft = context.read<CatchDraft>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('无法识别到鱼种'),
        content: const Text('上传的图片中未检测到鱼类。\n你可以重新选择照片，或仍然添加并归类到“其它”。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _classifyAsOther(draft);
            },
            child: const Text('仍然添加到其它'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(_showNewPhotoPickerSheet());
            },
            child: const Text('重新选择照片'),
          ),
        ],
      ),
    );
  }

  void _classifyAsOther(CatchDraft draft) {
    draft.aiIsFish = false;
    draft.aiSpeciesZh = SpeciesCatalog.otherSpeciesZh;
    draft.aiTaxonomyZh = '未识别分类';
    draft.aiInCatalog = true;
    draft.aiIdentifyValidForMediaSeq = draft.aiMediaSeq;
    draft.aiCachedScientificName = SpeciesCatalog.otherScientificName;
    draft.aiCachedConfidence = 0;
    draft.aiCachedApiFailed = false;
    draft.aiPendingNotFishDialog = false;
    draft.aiPendingIdentifyFailureSnack = false;
    draft.signalListeners();
    _programmaticSpeciesUpdate = true;
    _speciesController.text = SpeciesCatalog.otherSpeciesZh;
    _programmaticSpeciesUpdate = false;
    setState(() {
      _aiLoading = false;
      _identifyFailed = false;
      _aiScientificName = SpeciesCatalog.otherScientificName;
      _aiConfidence = 0;
    });
  }

  Future<bool> _showImageAuthorizationDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('图片授权'),
        content: const Text(
          '您正在上传一个图鉴中暂无记录的新鱼种。\n\n'
          '是否同意将您上传的照片作为该鱼种在公共物种图鉴中的展示图片？\n\n'
          '如不授权，物种图片将显示为"图片待上传"。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('不授权'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('授权使用'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _pickGallery() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: CatchPublishImageConfig.pickerQuality,
    );
    if (x == null || !mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    final draft = context.read<CatchDraft>();
    _latestUploadSource = AnalyticsProps.sourceAlbum;
    draft.setPickedImageBytes(bytes);
    _resetSpeciesStateForNewImage(draft);
    await _runIdentification(draft);
  }

  Future<void> _pickCamera() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: CatchPublishImageConfig.pickerQuality,
    );
    if (x == null || !mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    final draft = context.read<CatchDraft>();
    _latestUploadSource = AnalyticsProps.sourceCamera;
    draft.setPickedImageBytes(bytes);
    _resetSpeciesStateForNewImage(draft);
    await _runIdentification(draft);
  }

  Future<void> _openSelectLocation() async {
    final draft = context.read<CatchDraft>();
    _persistEditingToDraft(draft);
    await context.push<String?>('/select-location');
    if (!mounted) return;
    _restoreEditingFromDraft(context.read<CatchDraft>());
    setState(() {});
  }

  Future<void> _showNewPhotoPickerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: AppColors.primaryContainer),
                  title: const Text('从相册选择'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_pickGallery());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primaryContainer),
                  title: const Text('拍照'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_pickCamera());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _publish() async {
    if (_publishBusy) return;
    final draft = context.read<CatchDraft>();
    if (widget.editingPublishedId != null &&
        draft.editingReviewStatus.blocksEditingWhilePending) {
      return;
    }
    // 识别未完成且无手填鱼种时禁止发布，避免误发成「未确定」或沿用陈旧状态。
    if (_aiLoading && _speciesController.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('请等待 AI 识别结束，或先手动填写鱼种'),
        ),
      );
      return;
    }
    _publishBusy = true;
    try {
      final repo = context.read<CatchRepository>();
      final analytics = context.read<AnalyticsClient>();
      final api = context.read<ApiClient>();

      final manualSpeciesText = _speciesController.text.trim();
      final aiSuccess =
          _aiScientificName != null && _aiScientificName!.isNotEmpty && _aiScientificName != '—';
      final String speciesOrigin;
      final String species;
      if (manualSpeciesText.isNotEmpty) {
        speciesOrigin = 'manual';
        species = manualSpeciesText;
      } else if (aiSuccess) {
        speciesOrigin = 'ai';
        species = SpeciesCatalog.displayZhForScientific(_aiScientificName!);
      } else {
        speciesOrigin = 'default';
        species = '未确定';
      }

      final imagePresent = (draft.imageBytes != null && draft.imageBytes!.isNotEmpty) ||
          (draft.imageUrlFallback != null && draft.imageUrlFallback!.isNotEmpty);
      final locationType = (draft.lat != null && draft.lng != null)
          ? 'gps'
          : (draft.locationLabel == '未标注位置' ? 'skip' : 'fuzzy');

      final weightParsed = _metricOrZero(_weightController.text);
      final lengthParsed = _metricOrZero(_lengthController.text);

      analytics.trackFireAndForget(
        AnalyticsEvents.uploadClick,
        properties: <String, dynamic>{
          AnalyticsProps.entryPosition: 'edit_catch_publish',
        },
      );

      final resolvedScientific = SpeciesCatalog.resolveScientificNameFromUserInput(species);
      final aiSpeciesZhRaw = draft.aiSpeciesZh?.trim();
      final speciesZhForPublish =
          (aiSpeciesZhRaw == null || aiSpeciesZhRaw.isEmpty || aiSpeciesZhRaw == '未确定')
              ? species
              : aiSpeciesZhRaw;
      draft.scientificName = resolvedScientific;
      draft.notes = _notesController.text.trim();
      draft.weightKg = weightParsed;
      draft.lengthCm = lengthParsed;

      if (!draft.aiInCatalog &&
          resolvedScientific.isNotEmpty &&
          resolvedScientific != 'Indeterminate' &&
          resolvedScientific != 'Unnamed species' &&
          widget.editingPublishedId == null) {
        final authorized = await _showImageAuthorizationDialog();
        if (!mounted) return;
        draft.imageAuthorized = authorized;
      }

      if (!mounted) return;

      final editingId = widget.editingPublishedId;
      PublishedCatch? original;
      try {
        if (editingId != null) {
          original = await repo.getById(editingId);
        }
      } on ApiException catch (e) {
        if (!mounted) return;
        _showPublishFailure(e);
        return;
      } catch (e) {
        if (!mounted) return;
        _showPublishFailure(ApiException(message: e.toString()));
        return;
      }
      if (!mounted) return;

      final saved = draft.buildPublishedForSave(original: original);
      final imageBytesForPublish = draft.imageBytes;
      final taxonomyZh = draft.aiTaxonomyZh;
      final imageAuthorized = draft.imageAuthorized;
      final needSpeciesCatalogCreate = !draft.aiInCatalog &&
          resolvedScientific.isNotEmpty &&
          resolvedScientific != 'Indeterminate' &&
          resolvedScientific != 'Unnamed species' &&
          editingId == null;

      final successProps = <String, dynamic>{
        'species_origin': speciesOrigin,
        'ai_success': aiSuccess,
        'image_present': imagePresent,
        'location_type': locationType,
        'manual_species_input_count': _manualSpeciesInputCount,
        'upload_flow_id': draft.activeUploadFlowId,
      };
      final uploadFlowGuard = draft.activeUploadFlowId;
      final publishStartedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;

      if (!mounted) return;
      context.go('/home');

      unawaited(_runPublishAfterNavigate(
        repo: repo,
        api: api,
        analytics: analytics,
        draft: draft,
        saved: saved,
        imageBytesForPublish: imageBytesForPublish,
        updating: editingId != null,
        updateId: editingId,
        speciesZhForPublish: speciesZhForPublish,
        taxonomyZh: taxonomyZh,
        imageAuthorized: imageAuthorized,
        needSpeciesCatalogCreate: needSpeciesCatalogCreate,
        resolvedScientific: resolvedScientific,
        successProps: successProps,
        editingPublishedIdForRetry: editingId,
        uploadFlowGuard: uploadFlowGuard,
        publishStartedAtMs: publishStartedAtMs,
      ));
    } finally {
      _publishBusy = false;
    }
  }

  Future<void> _runPublishAfterNavigate({
    required CatchRepository repo,
    required ApiClient api,
    required AnalyticsClient analytics,
    required CatchDraft draft,
    required PublishedCatch saved,
    required Uint8List? imageBytesForPublish,
    required bool updating,
    required String? updateId,
    required String speciesZhForPublish,
    required String? taxonomyZh,
    required bool imageAuthorized,
    required bool needSpeciesCatalogCreate,
    required String resolvedScientific,
    required Map<String, dynamic> successProps,
    required String? editingPublishedIdForRetry,
    required String? uploadFlowGuard,
    required int publishStartedAtMs,
  }) async {
    try {
      if (needSpeciesCatalogCreate) {
        try {
          final formFields = <String, dynamic>{
            'scientific_name': resolvedScientific,
            'species_zh': speciesZhForPublish,
            'taxonomy_zh': taxonomyZh ?? '',
            'image_authorized': imageAuthorized.toString(),
          };
          if (imageAuthorized &&
              imageBytesForPublish != null &&
              imageBytesForPublish.isNotEmpty) {
            final form = FormData.fromMap(<String, dynamic>{
              ...formFields,
              'image': MultipartFile.fromBytes(
                imageBytesForPublish,
                filename: 'species.jpg',
                contentType: MediaType('image', 'jpeg'),
              ),
            });
            await api.postMultipart(SpeciesCatalogEndpoints.create, data: form);
          } else {
            await api.post(SpeciesCatalogEndpoints.create, data: formFields);
          }
        } catch (e) {
          debugPrint('[publish] species catalog create failed (non-fatal): $e');
        }
      }

      await repo.publish(
        saved,
        imageBytes: imageBytesForPublish,
        updating: updating,
        updateId: updateId,
        speciesZh: speciesZhForPublish,
        taxonomyZh: taxonomyZh,
        imageAuthorized: imageAuthorized,
      );
    } on ApiException catch (e) {
      _showPublishFailureFromRoot(e, editingPublishedIdForRetry: editingPublishedIdForRetry);
      return;
    } on PersistenceException catch (e) {
      _showPublishFailureFromRoot(
        ApiException(message: e.message),
        editingPublishedIdForRetry: editingPublishedIdForRetry,
      );
      return;
    } catch (e) {
      _showPublishFailureFromRoot(
        ApiException(message: e.toString()),
        editingPublishedIdForRetry: editingPublishedIdForRetry,
      );
      return;
    }

    if (draft.activeUploadFlowId == uploadFlowGuard) {
      draft.clearForNewRecord();
    }
    analytics.trackFireAndForget(
      AnalyticsEvents.uploadSuccess,
      properties: <String, dynamic>{
        AnalyticsProps.source: _latestUploadSource,
        AnalyticsProps.uploadDurationMs:
            DateTime.now().toUtc().millisecondsSinceEpoch - publishStartedAtMs,
        AnalyticsProps.imageId: saved.id,
        AnalyticsProps.fileSize: imageBytesForPublish?.length,
        ...successProps,
      },
    );
  }

  void _presentPublishFailure(
    BuildContext anchorContext,
    ApiException e, {
    required String? editingPublishedIdForRetry,
  }) {
    ScaffoldMessenger.of(anchorContext).clearSnackBars();
    ScaffoldMessenger.of(anchorContext).showSnackBar(
      SnackBar(
        content: Text(e.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
    showDialog<void>(
      context: anchorContext,
      builder: (ctx) => AlertDialog(
        title: const Text('发布失败'),
        content: Text(e.message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final router = GoRouter.of(anchorContext);
              if (editingPublishedIdForRetry != null &&
                  editingPublishedIdForRetry.isNotEmpty) {
                router.push('/edit-catch', extra: editingPublishedIdForRetry);
              } else {
                router.push('/edit-catch');
              }
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  void _showPublishFailure(ApiException e) {
    if (!mounted) return;
    _presentPublishFailure(
      context,
      e,
      editingPublishedIdForRetry: widget.editingPublishedId,
    );
  }

  void _showPublishFailureFromRoot(ApiException e, {required String? editingPublishedIdForRetry}) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _presentPublishFailure(
      ctx,
      e,
      editingPublishedIdForRetry: editingPublishedIdForRetry,
    );
  }

  String get _headlineSpecies {
    if (_aiLoading) return '识别中…';
    if (_identifyFailed) return '请手动填写鱼种';
    final s = _aiScientificName;
    if (s == null || s.isEmpty || s == '—') return '待添加照片';
    return SpeciesCatalog.displayZhForScientific(s);
  }

  /// 上传流程中点叉：放弃草稿并回首页；编辑已发布条目则仅返回上一页。
  void _onClosePressed(BuildContext context) {
    if (widget.editingPublishedId == null) {
      context.read<CatchDraft>().clearForNewRecord();
      context.go('/home');
    } else {
      context.pop();
    }
  }

  String get _confidenceLabel {
    if (_aiLoading) return '…';
    if (_identifyFailed) return '—';
    final c = _aiConfidence;
    if (c == null) return '—';
    return '${(c.clamp(0, 1) * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<CatchDraft>();
    final topPad = MediaQuery.paddingOf(context).top;
    final reviewLocksEditing = widget.editingPublishedId != null &&
        draft.editingReviewStatus.blocksEditingWhilePending;
    final reviewBanner = reviewLocksEditing ? draft.editingReviewStatus.detailHint : '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
          if (reviewBanner.isNotEmpty)
            Material(
              color: AppColors.surfaceContainerHigh.withValues(alpha: 0.9),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, size: 20, color: AppColors.cyanNav.withValues(alpha: 0.95)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        reviewBanner,
                        style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.onSurface.withValues(alpha: 0.9)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: topPad, left: 4, right: 8, bottom: 8),
            child: Stack(
              alignment: Alignment.center,
                children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => _onClosePressed(context),
                    icon: const Icon(Icons.close, color: AppColors.cyanNav, size: 26),
                  ),
                  ),
                  Text(
                    '编辑鱼获详情',
                  style: AppFont.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    color: AppColors.cyanNav,
                  ),
                  ),
                ],
            ),
          ),
          Expanded(
            child: IgnorePointer(
              ignoring: reviewLocksEditing,
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: CatchUi.photoAspectWidthOverHeight,
                    child: Stack(
                        fit: StackFit.expand,
                      children: [
                          CatchImageDisplay(
                            memoryBytes: draft.imageBytes,
                            networkUrlFallback: draft.imageUrlFallback,
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 100,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                    Colors.black.withValues(alpha: 0.55),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                            right: 16,
                          bottom: 16,
                            child: Material(
                              color: AppColors.primaryContainer,
                              shape: const CircleBorder(),
                              elevation: 6,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _showNewPhotoPickerSheet,
                                child: const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Icon(Icons.add_photo_alternate_outlined, color: AppColors.onPrimaryContainer, size: 26),
                                ),
                              ),
                            ),
                          ),
                          if (_aiLoading)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.4),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3.5,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'AI 识别中…',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.9),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          ),
                        ),
                      ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _AiSpeciesCard(
                    headlineSpecies: _headlineSpecies,
                    confidenceLabel: _confidenceLabel,
                    loading: _aiLoading,
                    speciesController: _speciesController,
                    speciesFocusNode: _speciesFocusNode,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricInput(
                          label: '重量 (KG)',
                          controller: _weightController,
                          hintText: '请输入',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _MetricInput(
                          label: '长度 (CM)',
                          controller: _lengthController,
                          hintText: '请输入',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: AppColors.surfaceContainerHigh.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _openSelectLocation,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '捕获地点',
                                    style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 1.2,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    draft.locationLabel,
                                    style: AppFont.manrope(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant.withValues(alpha: 0.6)),
                          ],
                        ),
                      ),
                    ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                    controller: _notesController,
                    maxLines: 5,
                    style: const TextStyle(color: AppColors.onSurface, height: 1.45),
                          decoration: InputDecoration(
                      hintText: '添加捕获心得或使用的饵料…',
                      hintStyle: TextStyle(color: AppColors.onSurfaceVariant.withValues(alpha: 0.55)),
                            filled: true,
                      fillColor: AppColors.surfaceContainerHigh.withValues(alpha: 0.55),
                            border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.15)),
                            ),
                            focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.cyanNav.withValues(alpha: 0.5)),
                      ),
                      contentPadding: const EdgeInsets.all(18),
                    ),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.paddingOf(context).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF22d3ee), Color(0xFF2563eb)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22d3ee).withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: reviewLocksEditing ? null : _publish,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                            Icon(
                              reviewLocksEditing ? Icons.lock_outline_rounded : Icons.send_rounded,
                              color: const Color(0xFF0f172a),
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              reviewLocksEditing ? '审核中' : '发布鱼获',
                              style: AppFont.manrope(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: const Color(0xFF0f172a),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
    );
  }
}

class _AiSpeciesCard extends StatelessWidget {
  const _AiSpeciesCard({
    required this.headlineSpecies,
    required this.confidenceLabel,
    required this.loading,
    required this.speciesController,
    required this.speciesFocusNode,
  });

  final String headlineSpecies;
  final String confidenceLabel;
  final bool loading;
  final TextEditingController speciesController;
  final FocusNode speciesFocusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF222a3d).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.psychology_outlined, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 智能识别',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headlineSpecies,
                      style: AppFont.manrope(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    confidenceLabel,
                    style: AppFont.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.secondaryFixed,
                    ),
                  ),
                  Text(
                    '匹配度',
                    style: TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: AppColors.surfaceContainerHighest,
                valueColor: const AlwaysStoppedAnimation(AppColors.cyanNav),
              ),
            ),
          const SizedBox(height: 14),
          SpeciesCatalogSearchField(
            controller: speciesController,
            focusNode: speciesFocusNode,
          ),
        ],
      ),
    );
  }
}

class _MetricInput extends StatelessWidget {
  const _MetricInput({
    required this.label,
    required this.controller,
    required this.hintText,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF222a3d).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: AppFont.manrope(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: hintText,
              hintStyle: AppFont.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 2,
            width: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                colors: [
                  AppColors.cyanNav.withValues(alpha: 0.2),
                  AppColors.cyanNav,
                  AppColors.cyanNav.withValues(alpha: 0.2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
