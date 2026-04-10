import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

class AdminSparklineCard extends StatelessWidget {
  const AdminSparklineCard({
    super.key,
    required this.title,
    required this.values,
    required this.color,
    this.subtitle,
  });

  final String title;
  final List<double> values;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return _shell(
        child: Center(
          child: Text(
            'No data',
            style: AppFont.manrope(
                fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
        ),
      );
    }
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final pad = maxV == minV ? 1.0 : (maxV - minV) * 0.08;
    final minY = (minV - pad).clamp(0.0, double.infinity);
    final maxY = maxV + pad;

    return _shell(
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (values.length - 1).clamp(0, 999).toDouble(),
          minY: minY,
          maxY: maxY == minY ? minY + 1 : maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.12),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(
                  v == v.roundToDouble()
                      ? '${v.round()}'
                      : v.toStringAsFixed(1),
                  style: AppFont.manrope(
                      fontSize: 9, color: AppColors.onSurfaceVariant),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: values.length <= 14,
                interval: values.length > 7 ? 2 : 1,
                getTitlesWidget: (v, _) {
                  final i = v.round();
                  if (i < 0 || i >= values.length)
                    return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '$i',
                      style: AppFont.manrope(
                          fontSize: 9, color: AppColors.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i])
              ],
              isCurved: true,
              color: color,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData:
                  BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shell({required Widget child}) {
    return Card(
      color: AppColors.surfaceContainer,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    AppFont.manrope(fontWeight: FontWeight.w700, fontSize: 13)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!,
                  style: AppFont.manrope(
                      fontSize: 10, color: AppColors.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),
            SizedBox(height: 120, child: child),
          ],
        ),
      ),
    );
  }
}

class AdminOverviewCoreFunnel extends StatelessWidget {
  const AdminOverviewCoreFunnel({super.key, required this.steps});

  final List<({String label, num value})> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final maxV = steps.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final denom = maxV > 0 ? maxV : 1;

    return Card(
      color: AppColors.surfaceContainer,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Core Funnel',
                style:
                    AppFont.manrope(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              'app_launch -> upload_click -> upload_success -> ai_identify_result -> species_unlock',
              style: AppFont.manrope(
                  fontSize: 11, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _FunnelStepRow(
                  label: steps[i].label,
                  value: steps[i].value,
                  max: denom,
                  color: _c(i)),
            ],
          ],
        ),
      ),
    );
  }

  Color _c(int i) {
    const colors = [
      AppColors.cyanNav,
      AppColors.secondaryFixed,
      AppColors.primaryContainer,
      Color(0xFFa78bfa),
      Color(0xFFfb923c)
    ];
    return colors[i % colors.length];
  }
}

class _FunnelStepRow extends StatelessWidget {
  const _FunnelStepRow(
      {required this.label,
      required this.value,
      required this.max,
      required this.color});

  final String label;
  final num value;
  final num max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = max > 0 ? (value / max).clamp(0.0, 1.0).toDouble() : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: Text(label,
                    style: AppFont.manrope(
                        fontWeight: FontWeight.w600, fontSize: 13))),
            Text(value.round().toString(),
                style:
                    AppFont.manrope(fontWeight: FontWeight.w800, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: AppColors.surfaceContainerHighest,
            color: color,
          ),
        ),
      ],
    );
  }
}

class AdminMixBar extends StatelessWidget {
  const AdminMixBar({super.key, required this.label, required this.segments});

  final String label;
  final List<({String name, num value, Color color})> segments;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<num>(0, (a, b) => a + b.value);
    if (total <= 0) {
      return Card(
        color: AppColors.surfaceContainerLow,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text('$label: no data',
              style: AppFont.manrope(
                  fontSize: 12, color: AppColors.onSurfaceVariant)),
        ),
      );
    }
    return Card(
      color: AppColors.surfaceContainer,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    AppFont.manrope(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    for (final s in segments)
                      if (s.value > 0)
                        Expanded(
                            flex: s.value.round().clamp(1, 999999),
                            child: Container(color: s.color)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
