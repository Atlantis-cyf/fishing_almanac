import 'package:flutter/material.dart';

import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

/// 与后端 parseAdminAnalyticsQuery 对齐的筛选条。
class AdminAnalyticsFilterBar extends StatelessWidget {
  const AdminAnalyticsFilterBar({
    super.key,
    required this.timeRange,
    required this.onTimeRangeChanged,
    required this.platformValue,
    required this.onPlatformChanged,
    required this.platformOptions,
    required this.onApply,
    this.entryPositionValue,
    this.onEntryPositionChanged,
    this.entryPositionOptions = const <String>[],
    this.customFromController,
    this.customToController,
  });

  final String timeRange;
  final ValueChanged<String> onTimeRangeChanged;
  final String? platformValue;
  final ValueChanged<String?> onPlatformChanged;
  final List<String> platformOptions;
  final VoidCallback onApply;
  final String? entryPositionValue;
  final ValueChanged<String?>? onEntryPositionChanged;
  final List<String> entryPositionOptions;
  final TextEditingController? customFromController;
  final TextEditingController? customToController;

  static const timeOptions = ['today', '7d', '14d', '30d', 'custom'];

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
                    DropdownMenuItem(value: '14d', child: Text('近 14 天')),
                    DropdownMenuItem(value: '30d', child: Text('近 30 天')),
                    DropdownMenuItem(value: 'custom', child: Text('自定义')),
                  ],
                  onChanged: (v) {
                    if (v != null) onTimeRangeChanged(v);
                  },
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    initialValue: platformOptions.contains(platformValue)
                        ? platformValue
                        : null,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'platform',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('全部平台'),
                      ),
                      ...platformOptions.map(
                        (v) =>
                            DropdownMenuItem<String>(value: v, child: Text(v)),
                      ),
                    ],
                    onChanged: onPlatformChanged,
                  ),
                ),
                if (onEntryPositionChanged != null)
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          entryPositionOptions.contains(entryPositionValue)
                              ? entryPositionValue
                              : null,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'entry_position',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('全部入口'),
                        ),
                        ...entryPositionOptions.map(
                          (v) => DropdownMenuItem<String>(
                              value: v, child: Text(v)),
                        ),
                      ],
                      onChanged: onEntryPositionChanged,
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
