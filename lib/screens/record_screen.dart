import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/analytics/analytics_client.dart';
import 'package:fishing_almanac/analytics/analytics_events.dart';
import 'package:fishing_almanac/analytics/analytics_props.dart';
import 'package:fishing_almanac/state/catch_draft.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/catch_ui_constants.dart';
import 'package:fishing_almanac/widgets/catch_image_display.dart';
import 'package:fishing_almanac/widgets/photo_adjust_dialog.dart';
import 'package:fishing_almanac/theme/app_font.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CatchDraft>().clearForNewRecord();
    });
  }

  Future<void> _pickPhoto() async {
    context.read<AnalyticsClient>().trackFireAndForget(
          AnalyticsEvents.uploadClick,
          properties: <String, dynamic>{
            AnalyticsProps.entryPosition: 'record_photo_picker',
          },
        );
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (x == null || !mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    context.read<CatchDraft>().setPickedImageBytes(bytes);
  }

  Future<void> _openAdjustPhoto(CatchDraft draft) async {
    await showPhotoAdjustDialog(
      context,
      memoryBytes: draft.imageBytes,
      networkUrlFallback: draft.imageUrlFallback,
      title: '调整上传照片',
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<CatchDraft>();
    final hasPhoto = draft.imageBytes != null && draft.imageBytes!.isNotEmpty;

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            decoration: BoxDecoration(
              color: AppColors.slate900.withValues(alpha: 0.6),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryContainer.withValues(alpha: 0.08),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.cyanNav),
                  ),
                  Text(
                    '记录鱼获',
                    style: AppFont.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: AppColors.cyanNav,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '步骤 1/2',
                    style: TextStyle(fontSize: 12, color: AppColors.slateNavInactive),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: 0.5,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        valueColor: const AlwaysStoppedAnimation(AppColors.primaryContainer),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '记录鱼获瞬间',
                    style: AppFont.manrope(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cyanNav.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 18, color: AppColors.cyanNav.withValues(alpha: 0.85)),
                        const SizedBox(width: 8),
                        Text(
                          'AI 将自动为您识别鱼种',
                          style: TextStyle(fontSize: 13, color: AppColors.cyanNav.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _pickPhoto,
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 2, style: BorderStyle.solid),
                        ),
                        child: hasPhoto
                            ? Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AspectRatio(
                                    aspectRatio: CatchUi.photoAspectWidthOverHeight,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () => _openAdjustPhoto(draft),
                                            child: CatchImageDisplay(memoryBytes: draft.imageBytes),
                                          ),
                                        ),
                                        Positioned(
                                          left: 12,
                                          bottom: 12,
                                          child: Material(
                                            color: AppColors.primaryContainer,
                                            shape: const CircleBorder(),
                                            child: InkWell(
                                              customBorder: const CircleBorder(),
                                              onTap: _pickPhoto,
                                              child: const Padding(
                                                padding: EdgeInsets.all(10),
                                                child: Icon(Icons.photo_library_outlined, size: 20, color: AppColors.onPrimaryContainer),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: 12,
                                          bottom: 12,
                                          child: Material(
                                            color: AppColors.primaryContainer,
                                            shape: const CircleBorder(),
                                            child: InkWell(
                                              customBorder: const CircleBorder(),
                                              onTap: () => _openAdjustPhoto(draft),
                                              child: const Padding(
                                                padding: EdgeInsets.all(10),
                                                child: Icon(Icons.crop_rotate, size: 20, color: AppColors.onPrimaryContainer),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : Column(
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.primaryContainer.withValues(alpha: 0.2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primaryContainer.withValues(alpha: 0.15),
                                          blurRadius: 30,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.add_a_photo_outlined,
                                      size: 40,
                                      color: AppColors.primaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '点击打开相册',
                                    style: AppFont.manrope(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '仅选择照片，不会跳转下一步',
                                    style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryContainer.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.lightbulb_outline, color: AppColors.secondaryFixed),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '拍摄建议',
                                style: AppFont.manrope(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '请确保鱼身完整且光线充足，侧面平放拍摄识别效果最佳。避免手指遮挡关键特征。',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.paddingOf(context).bottom),
            decoration: BoxDecoration(
              color: AppColors.slate900.withValues(alpha: 0.85),
              border: Border(top: BorderSide(color: AppColors.cyanNav.withValues(alpha: 0.08))),
            ),
            child: FilledButton(
              onPressed: () {
                context.read<AnalyticsClient>().trackFireAndForget(
                      AnalyticsEvents.uploadClick,
                      properties: <String, dynamic>{
                        AnalyticsProps.entryPosition: 'record_next_step',
                      },
                    );
                context.push('/select-location');
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.onPrimaryContainer,
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '下一步：选择位置',
                    style: AppFont.manrope(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
