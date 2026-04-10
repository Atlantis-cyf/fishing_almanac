import 'package:flutter/material.dart';

import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

/// 与 [AdminAnalyticsTabBody] 配合的看板展示模式。
enum AnalyticsDashboardMode {
  overview,
  uploadFunnel,
  aiIdentify,
  collectionGrowth,
}

/// 从 summary Map 安全取数值。
num readSummaryNum(Map<String, dynamic>? s, String key) {
  if (s == null) return 0;
  final v = s[key];
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse(v.toString()) ?? 0;
}

/// 用于空态横幅：各 Tab 核心字段全为 0。
bool isSummaryEffectivelyEmpty(
  AnalyticsDashboardMode mode,
  Map<String, dynamic>? s,
) {
  if (s == null || s.isEmpty) return true;
  switch (mode) {
    case AnalyticsDashboardMode.overview:
      return readSummaryNum(s, 'app_launch_count') +
              readSummaryNum(s, 'active_users_uv') +
              readSummaryNum(s, 'upload_click_count') +
              readSummaryNum(s, 'species_unlock_count') +
              readSummaryNum(s, 'ai_identify_result_count') ==
          0;
    case AnalyticsDashboardMode.uploadFunnel:
      return readSummaryNum(s, 'upload_click_count') +
              readSummaryNum(s, 'upload_success_count') +
              readSummaryNum(s, 'upload_click_uv') ==
          0;
    case AnalyticsDashboardMode.aiIdentify:
      return readSummaryNum(s, 'identify_start_count') +
              readSummaryNum(s, 'identify_result_count') +
              readSummaryNum(s, 'identify_fail_count') ==
          0;
    case AnalyticsDashboardMode.collectionGrowth:
      return readSummaryNum(s, 'species_unlock_count') +
              readSummaryNum(s, 'collection_view_uv') +
              readSummaryNum(s, 'species_detail_view_uv') +
              readSummaryNum(s, 'overview_collection_view_count') ==
          0;
  }
}

/// 单张 KPI 卡片。
class AdminKpiCard extends StatelessWidget {
  const AdminKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.tooltipMessage,
  });

  final String label;
  final String value;
  final String? subtitle;
  final String? tooltipMessage;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppFont.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (tooltipMessage != null && tooltipMessage!.isNotEmpty)
                  Tooltip(
                    message: tooltipMessage,
                    triggerMode: TooltipTriggerMode.tap,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.help_outline,
                        size: 16,
                        color:
                            AppColors.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: AppFont.manrope(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: AppColors.primary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: AppFont.manrope(
                  fontSize: 11,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 全零时的提示条。
class AdminAnalyticsEmptyHint extends StatelessWidget {
  const AdminAnalyticsEmptyHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surfaceContainerLow,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: AppColors.cyanNav),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当前窗口内几乎没有事件数据',
                    style: AppFont.manrope(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '• 构建 App 时需加 --dart-define=ENABLE_ANALYTICS=true 才会上报\n'
              '• platform 留空表示全平台；填错会筛空\n'
              '• 数据落在 Supabase analytics_events，经视图聚合后展示',
              style: AppFont.manrope(
                fontSize: 12,
                height: 1.35,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 区块标题 + 留白。
class AdminDashSectionTitle extends StatelessWidget {
  const AdminDashSectionTitle(this.text, {super.key, this.subtitle});

  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: AppFont.manrope(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: AppFont.manrope(
                  fontSize: 11, color: AppColors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
