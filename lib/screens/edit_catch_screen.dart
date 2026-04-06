import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/analytics/analytics_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/repositories/catch_repository.dart';
import 'package:fishing_almanac/repositories/persistence_exception.dart';
import 'package:fishing_almanac/services/species_identification.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';
import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/state/catch_draft.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/catch_ui_constants.dart';
import 'package:fishing_almanac/widgets/catch_image_display.dart';
import 'package:fishing_almanac/widgets/publish_loading_overlay.dart';
import 'package:fishing_almanac/widgets/species_catalog_search_field.dart';
import 'package:google_fonts/google_fonts.dart';

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
  int _identifyToken = 0;
  bool _publishing = false;

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
      final draft = context.read<CatchDraft>();
      context.read<AnalyticsClient>().trackFireAndForget(
            'species_manual_input',
            properties: <String, dynamic>{
              'count': _manualSpeciesInputCount,
              'value_len': vv.length,
              'upload_flow_id': draft.activeUploadFlowId,
            },
          );
    });
  }

  @override
  void initState() {
    super.initState();
    _speciesController.addListener(_onSpeciesControllerChanged);
  }

  @override
  void dispose() {
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
    if (_synced) return;
    _synced = true;
    final draft = context.read<CatchDraft>();
    final id = widget.editingPublishedId;
    final analytics = context.read<AnalyticsClient>();
    draft.activeUploadFlowId = 'flow_${DateTime.now().toUtc().millisecondsSinceEpoch}';
    if (id != null) {
      analytics.trackFireAndForget(
        'upload_flow_start',
        properties: <String, dynamic>{
          'mode': 'edit_published',
          'upload_flow_id': draft.activeUploadFlowId,
        },
      );
      scheduleMicrotask(() => _hydrateEditing(id));
    } else {
      final hasImage =
          (draft.imageBytes != null && draft.imageBytes!.isNotEmpty) || (draft.imageUrlFallback != null && draft.imageUrlFallback!.isNotEmpty);
      analytics.trackFireAndForget(
        'upload_flow_start',
        properties: <String, dynamic>{
          'mode': 'new_or_draft',
          'has_image_initial': hasImage,
          'upload_flow_id': draft.activeUploadFlowId,
        },
      );
      if (hasImage) {
        analytics.trackFireAndForget(
          'upload_step_image_completed',
          properties: <String, dynamic>{
            'source': 'draft',
            'upload_flow_id': draft.activeUploadFlowId,
          },
        );
      }

      if (draft.scientificName.isNotEmpty) {
        _programmaticSpeciesUpdate = true;
        _speciesController.text = SpeciesCatalog.displayZhForScientific(draft.scientificName);
        _programmaticSpeciesUpdate = false;
      }
      _notesController.text = draft.notes;
      _weightController.text = _metricTextForDraft(draft.weightKg);
      _lengthController.text = _metricTextForDraft(draft.lengthCm);
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
    if (hasImage) {
      analytics.trackFireAndForget(
        'upload_step_image_completed',
        properties: <String, dynamic>{
          'source': 'published',
          'upload_flow_id': draft.activeUploadFlowId,
        },
      );
    }

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

  void _scheduleIdentify(CatchDraft draft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runIdentification(context.read<CatchDraft>());
    });
  }

  Future<void> _runIdentification(CatchDraft draft) async {
    final svc = context.read<SpeciesIdentificationService>();
    final analytics = context.read<AnalyticsClient>();
    final token = ++_identifyToken;

    final hasBytes = draft.imageBytes != null && draft.imageBytes!.isNotEmpty;
    final hasUrl = draft.imageUrlFallback != null && draft.imageUrlFallback!.isNotEmpty;
    analytics.trackFireAndForget(
      'ai_identify_requested',
      properties: <String, dynamic>{
        'has_bytes': hasBytes,
        'has_url': hasUrl,
        'upload_flow_id': draft.activeUploadFlowId,
      },
    );

    setState(() {
      _aiLoading = true;
      _identifyFailed = false;
    });
    try {
      final r = await svc.identifySpecies(
        imageBytes: draft.imageBytes,
        imageUrl: draft.imageUrlFallback,
      );
      if (!mounted || token != _identifyToken) return;
      setState(() {
        _aiLoading = false;
        _identifyFailed = false;
        _aiScientificName = r.scientificName;
        _aiConfidence = r.confidence;
      });
      final aiSuccess = r.scientificName.isNotEmpty && r.scientificName != '—';
      analytics.trackFireAndForget(
        'ai_identify_completed',
        properties: <String, dynamic>{
          'success': aiSuccess,
          'confidence': r.confidence,
          'upload_flow_id': draft.activeUploadFlowId,
        },
      );

      if (_speciesController.text.trim().isEmpty &&
          r.scientificName.isNotEmpty &&
          r.scientificName != '—') {
        _programmaticSpeciesUpdate = true;
        _speciesController.text = SpeciesCatalog.displayZhForScientific(r.scientificName);
        _programmaticSpeciesUpdate = false;
      }
    } on ApiException catch (e) {
      if (!mounted || token != _identifyToken) return;
      setState(() {
        _aiLoading = false;
        _identifyFailed = true;
        _aiScientificName = null;
        _aiConfidence = null;
      });
      analytics.trackFireAndForget(
        'ai_identify_failed',
        properties: <String, dynamic>{
          'error_type': 'ApiException',
          'message_len': e.message.length,
          'upload_flow_id': draft.activeUploadFlowId,
        },
      );
      _showIdentifyFailure(e);
    } catch (e) {
      if (!mounted || token != _identifyToken) return;
      setState(() {
        _aiLoading = false;
        _identifyFailed = true;
        _aiScientificName = null;
        _aiConfidence = null;
      });
      analytics.trackFireAndForget(
        'ai_identify_failed',
        properties: <String, dynamic>{
          'error_type': 'Exception',
          'upload_flow_id': draft.activeUploadFlowId,
        },
      );
      _showIdentifyFailure(e is ApiException ? e : ApiException(message: e.toString()));
    }
  }

  void _showIdentifyFailure(ApiException e) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          '识别失败，请手动填写\n${e.message}',
          style: const TextStyle(height: 1.35),
        ),
      ),
    );
  }

  Future<void> _pickGallery() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: CatchPublishImageConfig.pickerQuality,
    );
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    final draft = context.read<CatchDraft>();
    draft.setPickedImageBytes(bytes);
    context.read<AnalyticsClient>().trackFireAndForget(
          'upload_step_image_completed',
      properties: <String, dynamic>{
        'source': 'gallery',
        'upload_flow_id': draft.activeUploadFlowId,
      },
        );
    await _runIdentification(draft);
  }

  Future<void> _pickCamera() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: CatchPublishImageConfig.pickerQuality,
    );
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    final draft = context.read<CatchDraft>();
    draft.setPickedImageBytes(bytes);
    context.read<AnalyticsClient>().trackFireAndForget(
          'upload_step_image_completed',
      properties: <String, dynamic>{
        'source': 'camera',
        'upload_flow_id': draft.activeUploadFlowId,
      },
        );
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
    if (_publishing) return;
    final draft = context.read<CatchDraft>();
    if (widget.editingPublishedId != null &&
        draft.editingReviewStatus.blocksEditingWhilePending) {
      return;
    }
    // 立刻上锁，避免在首个 await 之前连点触发多次发布。
    setState(() => _publishing = true);
    if (!mounted) return;
    // 先让出事件循环并等一帧绘制完成，再跑后续同步准备；否则界面会卡在「发布鱼获」上。
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final repo = context.read<CatchRepository>();
    final analytics = context.read<AnalyticsClient>();

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

    final imagePresent = (draft.imageBytes != null && draft.imageBytes!.isNotEmpty) || (draft.imageUrlFallback != null && draft.imageUrlFallback!.isNotEmpty);
    final locationType = (draft.lat != null && draft.lng != null)
        ? 'gps'
        : (draft.locationLabel == '未标注位置' ? 'skip' : 'fuzzy');

    final weightParsed = _metricOrZero(_weightController.text);
    final lengthParsed = _metricOrZero(_lengthController.text);

    analytics.trackFireAndForget(
      'upload_step_publish_pressed',
      properties: <String, dynamic>{
        'species_origin': speciesOrigin,
        'ai_success': aiSuccess,
        'image_present': imagePresent,
        'location_type': locationType,
        'manual_species_input_count': _manualSpeciesInputCount,
        'upload_flow_id': draft.activeUploadFlowId,
      },
    );

    draft.scientificName = SpeciesCatalog.resolveScientificNameFromUserInput(species);
    draft.notes = _notesController.text.trim();
    draft.weightKg = weightParsed;
    draft.lengthCm = lengthParsed;
    try {
      final original =
          widget.editingPublishedId != null ? await repo.getById(widget.editingPublishedId!) : null;
      final saved = draft.buildPublishedForSave(original: original);
      await repo.publish(
        saved,
        imageBytes: draft.imageBytes,
        updating: widget.editingPublishedId != null,
        updateId: widget.editingPublishedId,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      analytics.trackFireAndForget(
        'upload_completed_failed',
        properties: <String, dynamic>{
          'error_type': 'ApiException',
          'message_len': e.message.length,
          'upload_flow_id': draft.activeUploadFlowId,
        },
      );
      _showPublishFailure(e);
      return;
    } on PersistenceException catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      analytics.trackFireAndForget(
        'upload_completed_failed',
        properties: <String, dynamic>{
          'error_type': 'PersistenceException',
          'message_len': e.message.length,
          'upload_flow_id': draft.activeUploadFlowId,
        },
      );
      _showPublishFailure(ApiException(message: e.message));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      analytics.trackFireAndForget(
        'upload_completed_failed',
        properties: <String, dynamic>{
          'error_type': 'Exception',
          'message': e.toString(),
          'upload_flow_id': draft.activeUploadFlowId,
        },
      );
      _showPublishFailure(ApiException(message: e.toString()));
      return;
    }
    if (!mounted) return;
    setState(() => _publishing = false);

    analytics.trackFireAndForget(
      'upload_completed_success',
      properties: <String, dynamic>{
        'species_origin': speciesOrigin,
        'ai_success': aiSuccess,
        'image_present': imagePresent,
        'location_type': locationType,
        'manual_species_input_count': _manualSpeciesInputCount,
        'upload_flow_id': draft.activeUploadFlowId,
      },
    );

    draft.clearForNewRecord();
    context.go('/home');
  }

  void _showPublishFailure(ApiException e) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(e.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发布失败'),
        content: Text(e.message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(_publish());
            },
            child: const Text('重试'),
          ),
        ],
      ),
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
                    onPressed: _publishing ? null : () => _onClosePressed(context),
                    icon: const Icon(Icons.close, color: AppColors.cyanNav, size: 26),
                  ),
                ),
                Text(
                  '编辑鱼获详情',
                  style: GoogleFonts.manrope(
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
              ignoring: _publishing || reviewLocksEditing,
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
                                    style: GoogleFonts.manrope(
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
                      onTap: (_publishing || reviewLocksEditing) ? null : _publish,
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
                              style: GoogleFonts.manrope(
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
          if (_publishing)
            const Positioned.fill(
              child: PublishLoadingOverlay(),
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
                      style: GoogleFonts.manrope(
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
                    style: GoogleFonts.manrope(
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
            style: GoogleFonts.manrope(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: hintText,
              hintStyle: GoogleFonts.manrope(
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
