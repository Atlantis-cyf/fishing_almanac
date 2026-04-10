import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

/// 开发模式下展示原始 JSON，默认折叠。
class AdminAnalyticsDebugPanel extends StatelessWidget {
  const AdminAnalyticsDebugPanel({
    super.key,
    required this.chunks,
  });

  /// 多块命名响应，例如 `primary` / `collection`。
  final Map<String, Object?> chunks;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || chunks.isEmpty) return const SizedBox.shrink();

    String pretty(Object? v) {
      try {
        return const JsonEncoder.withIndent('  ').convert(v);
      } catch (_) {
        return v.toString();
      }
    }

    return Card(
      color: AppColors.surfaceContainerLow,
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          title: Text(
            '调试：原始 API 响应',
            style: AppFont.manrope(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Text(
            '仅 Debug 构建可见；含 daily 全量字段',
            style: AppFont.manrope(
                fontSize: 11, color: AppColors.onSurfaceVariant),
          ),
          children: [
            for (final e in chunks.entries)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SelectionArea(
                    child: Text(
                      '[${e.key}]\n${pretty(e.value)}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        height: 1.25,
                        color: AppColors.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
