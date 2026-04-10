import 'package:flutter/material.dart';

import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

/// 与后端 [parseAdminAnalyticsQuery] 对齐的筛选条（方案 1：仅存 State，不写 URL）。
class AdminAnalyticsFilterBar extends StatelessWidget {
  const AdminAnalyticsFilterBar({
    super.key,
    required this.timeRange,
    required this.onTimeRangeChanged,
    required this.platformController,
    required this.onApply,
    this.entryPositionController,
    this.customFromController,
    this.customToController,
  });

  final String timeRange;
  final ValueChanged<String> onTimeRangeChanged;
  final TextEditingController platformController;
  final VoidCallback onApply;
  final TextEditingController? entryPositionController;
  final TextEditingController? customFromController;
  final TextEditingController? customToController;

  static const timeOptions = ['today', '7d', '30d', 'custom'];

  @override
  Widget build(BuildContext context) {
    final isCustom = timeRange == 'custom';

    return Card(
      color: AppColors.background,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '筛选',
              style: AppFont.manrope(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: timeOptions.contains(timeRange) ? timeRange : '7d',
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('今天')),
                    DropdownMenuItem(value: '7d', child: Text('近 7 天')),
                    DropdownMenuItem(value: '30d', child: Text('近 30 天')),
                    DropdownMenuItem(value: 'custom', child: Text('自定义')),
                  ],
                  onChanged: (v) {
                    if (v != null) onTimeRangeChanged(v);
                  },
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: platformController,
                    decoration: const InputDecoration(
                      labelText: 'platform（可选）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (entryPositionController != null)
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: entryPositionController,
                      decoration: const InputDecoration(
                        labelText: 'entry_position（可选）',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: onApply,
                  child: const Text('应用'),
                ),
              ],
            ),
            if (isCustom &&
                customFromController != null &&
                customToController != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: customFromController,
                      decoration: const InputDecoration(
                        labelText: 'from（ISO-8601）',
                        hintText: '2026-04-01T00:00:00.000Z',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: customToController,
                      decoration: const InputDecoration(
                        labelText: 'to（ISO-8601）',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
