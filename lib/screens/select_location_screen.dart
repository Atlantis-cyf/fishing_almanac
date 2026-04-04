import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/analytics/analytics_client.dart';
import 'package:fishing_almanac/data/image_urls.dart';
import 'package:fishing_almanac/state/catch_draft.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/widgets/catch_image_display.dart';
import 'package:google_fonts/google_fonts.dart';

class SelectLocationScreen extends StatefulWidget {
  const SelectLocationScreen({super.key});

  @override
  State<SelectLocationScreen> createState() => _SelectLocationScreenState();
}

class _SelectLocationScreenState extends State<SelectLocationScreen> {
  bool _offeredChoice = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_offeredChoice) return;
    _offeredChoice = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showLocationModeSheet(context);
    });
  }

  Future<void> _showLocationModeSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '选择位置方式',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  '精准 GPS、模糊城市或跳过，可随时在编辑页查看地图。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _applyGps(context);
                  },
                  icon: const Icon(Icons.gps_fixed),
                  label: const Text('使用当前 GPS'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _applyCityDialog(context);
                  },
                  icon: const Icon(Icons.location_city_outlined),
                  label: const Text('模糊城市'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _applySkip(context);
                  },
                  child: const Text('暂不标注位置'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _applyGps(BuildContext context) async {
    final draft = context.read<CatchDraft>();
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要定位权限才能获取 GPS')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      draft.setLocationFromGps(
        pos.latitude,
        pos.longitude,
        'GPS ${pos.latitude.toStringAsFixed(4)}°, ${pos.longitude.toStringAsFixed(4)}°',
      );
      if (context.mounted) setState(() {});
      context.read<AnalyticsClient>().trackFireAndForget(
            'upload_step_location_set',
            properties: <String, dynamic>{
              'mode': 'gps',
              'upload_flow_id': draft.activeUploadFlowId,
            },
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('定位失败：$e')),
        );
      }
    }
  }

  Future<void> _applyCityDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: '上海市');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('模糊城市'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '城市或钓点名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<CatchDraft>().setLocationFuzzy(ctrl.text.trim());
      setState(() {});
      context.read<AnalyticsClient>().trackFireAndForget(
            'upload_step_location_set',
            properties: <String, dynamic>{
              'mode': 'fuzzy_city',
              'upload_flow_id': context.read<CatchDraft>().activeUploadFlowId,
            },
          );
    }
  }

  void _applySkip(BuildContext context) {
    context.read<CatchDraft>().skipLocation();
    setState(() {});
    context.read<AnalyticsClient>().trackFireAndForget(
          'upload_step_location_set',
          properties: <String, dynamic>{
            'mode': 'skip',
            'upload_flow_id': context.read<CatchDraft>().activeUploadFlowId,
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<CatchDraft>();

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: Opacity(
              opacity: 0.6,
              child: Image.network(
                ImageUrls.selectLocationMap,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => Container(color: AppColors.surface),
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                colors: [Colors.transparent, Color(0xFF0b1326)],
                stops: [0, 0.9],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back, color: AppColors.cyanNav),
                      ),
                      Text(
                        '选择位置',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: AppColors.cyanNav,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _showLocationModeSheet(context),
                        child: const Text('重新选择'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.15)),
                      boxShadow: const [BoxShadow(blurRadius: 20)],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.place_outlined, color: AppColors.primaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            draft.locationLabel,
                            style: const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.1)),
                      boxShadow: const [BoxShadow(blurRadius: 24)],
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 96,
                            height: 96,
                            child: CatchImageDisplay(
                              memoryBytes: draft.imageBytes,
                              networkUrlFallback: draft.imageUrlFallback ?? ImageUrls.selectLocationThumb,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '当前草稿',
                                style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
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
                              if (draft.lat != null && draft.lng != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '${draft.lat!.toStringAsFixed(4)}°, ${draft.lng!.toStringAsFixed(4)}°',
                                  style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
                child: FilledButton(
                  onPressed: () => context.push('/edit-catch'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: const Color(0xFF22d3ee),
                    foregroundColor: const Color(0xFF0f172a),
                    shape: const StadiumBorder(),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '下一步：编辑鱼获详情',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 17),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
