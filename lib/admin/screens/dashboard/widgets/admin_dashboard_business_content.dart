import 'package:flutter/material.dart';

import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_dashboard_charts.dart';
import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_dashboard_debug_panel.dart';
import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_dashboard_layouts.dart';
import 'package:fishing_almanac/theme/app_colors.dart';

String _fmtInt(num v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
String _fmtRate(num v) => (v <= 1 && v >= 0)
    ? '${(v * 100).toStringAsFixed(1)}%'
    : '${v.toStringAsFixed(1)}%';
String _fmtMs(num? v) => v == null ? '-' : '${v.round()} ms';

List<Map<String, dynamic>> _sumDailyByDate(List<dynamic> rows) {
  final m = <String, Map<String, dynamic>>{};
  for (final raw in rows) {
    if (raw is! Map) continue;
    final r = Map<String, dynamic>.from(raw);
    final d = r['event_date']?.toString() ?? '';
    if (d.isEmpty) continue;
    final t = m.putIfAbsent(d, () => <String, dynamic>{'event_date': d});
    for (final e in r.entries) {
      if (e.key == 'event_date' || e.key == 'platform') continue;
      t[e.key] = readSummaryNum(t, e.key) + readSummaryNum(r, e.key);
    }
  }
  final keys = m.keys.toList()..sort();
  return [for (final k in keys) m[k]!];
}

List<double> _series(List<Map<String, dynamic>> rows, String key) =>
    [for (final r in rows) readSummaryNum(r, key).toDouble()];

class AdminDashboardBusinessContent extends StatelessWidget {
  const AdminDashboardBusinessContent({
    super.key,
    required this.mode,
    required this.cardWidth,
    required this.summary,
    required this.daily,
    this.extraSummaries = const {},
    this.extraDailies = const {},
    required this.debugChunks,
  });

  final AnalyticsDashboardMode mode;
  final double cardWidth;
  final Map<String, dynamic>? summary;
  final List<dynamic> daily;
  final Map<String, Map<String, dynamic>?> extraSummaries;
  final Map<String, List<dynamic>> extraDailies;
  final Map<String, Object?> debugChunks;

  @override
  Widget build(BuildContext context) {
    final w = cardWidth.clamp(148.0, 520.0);
    Widget card(Widget c) => SizedBox(width: w, child: c);
    switch (mode) {
      case AnalyticsDashboardMode.overview:
        return _overview(card);
      case AnalyticsDashboardMode.uploadFunnel:
        return _upload(card);
      case AnalyticsDashboardMode.aiIdentify:
        return _ai(card);
      case AnalyticsDashboardMode.collectionGrowth:
        return _collection(card);
    }
  }

  Widget _kpi(List<Widget> cards) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 12, runSpacing: 12, children: cards),
      );

  Widget _overview(Widget Function(Widget) card) {
    final ov = Map<String, dynamic>.from(summary ?? const {});
    final up = extraSummaries.values.firstWhere(
      (x) => x?['upload_click_uv'] != null || x?['upload_success_uv'] != null,
      orElse: () => const {},
    );
    final co = extraSummaries.values.firstWhere(
      (x) => x?['species_unlock_user_uv'] != null || x?['collection_view_uv'] != null,
      orElse: () => const {},
    );
    ov['upload_click_uv'] = readSummaryNum(up, 'upload_click_uv');
    ov['upload_success_uv'] = readSummaryNum(up, 'upload_success_uv');
    ov['species_unlock_user_uv'] = readSummaryNum(co, 'species_unlock_user_uv');
    ov['species_unlock_count'] = readSummaryNum(co, 'species_unlock_count');
    ov['collection_view_uv'] = readSummaryNum(co, 'collection_view_uv');

    final dailyRows = _sumDailyByDate(daily);
    final unlockRows = _sumDailyByDate(
      extraDailies.values.expand((e) => e).toList(),
    );
    final unlockSeries = _series(unlockRows, 'species_unlock_count');
    final funnel = <({String label, num value})>[
      (label: 'app_launch_uv', value: readSummaryNum(ov, 'app_launch_uv')),
      (label: 'upload_click_uv', value: readSummaryNum(ov, 'upload_click_uv')),
      (label: 'upload_success_uv', value: readSummaryNum(ov, 'upload_success_uv')),
      (
        label: 'ai_identify_success_uv',
        value: readSummaryNum(ov, 'ai_identify_success_uv')
      ),
      (
        label: 'species_unlock_user_uv',
        value: readSummaryNum(ov, 'species_unlock_user_uv')
      ),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        const AdminDashSectionTitle('概览'),
        _kpi([
          card(AdminKpiCard(label: 'DAU', value: _fmtInt(readSummaryNum(ov, 'active_users_uv')))),
          card(AdminKpiCard(label: '上传用户数', value: _fmtInt(readSummaryNum(ov, 'upload_click_uv')))),
          card(AdminKpiCard(label: '上传成功用户数', value: _fmtInt(readSummaryNum(ov, 'upload_success_uv')))),
          card(AdminKpiCard(label: 'AI识别成功用户数', value: _fmtInt(readSummaryNum(ov, 'ai_identify_success_uv')))),
          card(AdminKpiCard(label: '新增解锁用户数', value: _fmtInt(readSummaryNum(ov, 'species_unlock_user_uv')))),
          card(AdminKpiCard(label: '新增解锁次数', value: _fmtInt(readSummaryNum(ov, 'species_unlock_count')))),
          card(AdminKpiCard(label: '图鉴访问用户数', value: _fmtInt(readSummaryNum(ov, 'collection_view_uv')))),
          card(AdminKpiCard(label: '识别成功率', value: _fmtRate(readSummaryNum(ov, 'identify_success_rate')))),
        ]),
        AdminOverviewCoreFunnel(steps: funnel),
        const AdminDashSectionTitle('核心趋势'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              AdminSparklineCard(
                title: 'DAU趋势',
                values: _series(dailyRows, 'active_users_uv'),
                color: AppColors.cyanNav,
              ),
              const SizedBox(height: 12),
              AdminSparklineCard(
                title: '上传成功趋势',
                values: _series(dailyRows, 'upload_success_count'),
                color: AppColors.secondaryFixed,
              ),
              const SizedBox(height: 12),
              AdminSparklineCard(
                title: '新增解锁趋势',
                values: unlockSeries,
                color: const Color(0xFFfb923c),
              ),
            ],
          ),
        ),
        AdminAnalyticsDebugPanel(chunks: debugChunks),
      ],
    );
  }

  Widget _upload(Widget Function(Widget) card) {
    final s = summary ?? const <String, dynamic>{};
    final rows = _sumDailyByDate(daily);
    final clickUv = readSummaryNum(s, 'upload_click_uv');
    final successUv = readSummaryNum(s, 'upload_success_uv');
    final clickCount = readSummaryNum(s, 'upload_click_count');
    final successCount = readSummaryNum(s, 'upload_success_count');
    final rate = clickCount > 0 ? successCount / clickCount : 0;

    final mixRaw = s['entry_position_click_mix'];
    final mix = mixRaw is Map ? Map<String, dynamic>.from(mixRaw) : <String, dynamic>{};
    num cam = 0, alb = 0, oth = 0;
    mix.forEach((k, v) {
      final n = readSummaryNum(mix, k);
      final x = k.toLowerCase();
      if (x.contains('camera')) {
        cam += n;
      } else if (x.contains('album')) {
        alb += n;
      } else {
        oth += n;
      }
    });

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        const AdminDashSectionTitle('上传'),
        _kpi([
          card(AdminKpiCard(label: '上传点击用户数', value: _fmtInt(clickUv))),
          card(AdminKpiCard(label: '上传点击次数', value: _fmtInt(clickCount))),
          card(AdminKpiCard(label: '上传成功用户数', value: _fmtInt(successUv))),
          card(AdminKpiCard(label: '上传成功次数', value: _fmtInt(successCount))),
          card(AdminKpiCard(label: '上传成功率', value: _fmtRate(rate))),
          card(AdminKpiCard(
              label: '平均上传耗时',
              value: _fmtMs(_nullableNum(s, 'upload_avg_duration_ms')))),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdminMixBar(
            label: 'camera / album 占比',
            segments: [
              (name: 'camera', value: cam, color: AppColors.cyanNav),
              (name: 'album', value: alb, color: AppColors.secondaryFixed),
              (name: 'other', value: oth, color: AppColors.surfaceContainerHighest),
            ],
          ),
        ),
        const AdminDashSectionTitle('上传趋势'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdminSparklineCard(
            title: '上传成功次数趋势',
            values: _series(rows, 'upload_success_count'),
            color: AppColors.primaryContainer,
          ),
        ),
        AdminAnalyticsDebugPanel(chunks: debugChunks),
      ],
    );
  }

  Widget _ai(Widget Function(Widget) card) {
    final s = summary ?? const <String, dynamic>{};
    final rows = _sumDailyByDate(daily);
    final starts = readSummaryNum(s, 'identify_start_count');
    final succ = readSummaryNum(s, 'identify_result_count');
    final fail = readSummaryNum(s, 'identify_fail_count');
    final rate = starts > 0 ? succ / starts : 0;

    final distRaw = s['fail_reason_breakdown'];
    final dist = distRaw is Map ? Map<String, dynamic>.from(distRaw) : <String, dynamic>{};
    final chips = dist.entries.where((e) => readSummaryNum(dist, e.key) > 0).toList()
      ..sort((a, b) => readSummaryNum(dist, b.key).compareTo(readSummaryNum(dist, a.key)));

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        const AdminDashSectionTitle('AI'),
        _kpi([
          card(AdminKpiCard(label: '识别发起请求数', value: _fmtInt(starts))),
          card(AdminKpiCard(label: '识别成功请求数', value: _fmtInt(succ))),
          card(AdminKpiCard(label: '识别失败请求数', value: _fmtInt(fail))),
          card(AdminKpiCard(label: '识别成功率', value: _fmtRate(rate))),
          card(AdminKpiCard(
              label: '平均 latency',
              value: _fmtMs(_nullableNum(s, 'identify_latency_avg_ms')))),
          if (_nullableNum(s, 'identify_confidence_avg') != null)
            card(AdminKpiCard(
              label: '平均 confidence',
              value: _nullableNum(s, 'identify_confidence_avg')!.toStringAsFixed(3),
            )),
        ]),
        const AdminDashSectionTitle('失败原因分布'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: chips.isEmpty
              ? const Card(
                  color: AppColors.surfaceContainerLow,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无失败样本'),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in chips)
                      Chip(label: Text('${e.key}: ${_fmtInt(readSummaryNum(dist, e.key))}')),
                  ],
                ),
        ),
        const AdminDashSectionTitle('识别趋势'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              AdminSparklineCard(
                title: '识别发起请求数',
                values: _series(rows, 'identify_start_count'),
                color: AppColors.cyanNav,
              ),
              const SizedBox(height: 12),
              AdminSparklineCard(
                title: '识别成功请求数',
                values: _series(rows, 'identify_result_count'),
                color: AppColors.secondaryFixed,
              ),
            ],
          ),
        ),
        AdminAnalyticsDebugPanel(chunks: debugChunks),
      ],
    );
  }

  Widget _collection(Widget Function(Widget) card) {
    final s = summary ?? const <String, dynamic>{};
    final rows = _sumDailyByDate(daily);
    final colUv = readSummaryNum(s, 'collection_view_uv');
    final colCount = readSummaryNum(s, 'collection_view_count');
    final detailUv = readSummaryNum(s, 'species_detail_view_uv');
    final detailCount = readSummaryNum(s, 'species_detail_view_count');
    final unlockUv = readSummaryNum(s, 'species_unlock_user_uv');
    final unlockCount = readSummaryNum(s, 'species_unlock_count');

    final cards = <Widget>[
      card(AdminKpiCard(label: '图鉴访问用户数', value: _fmtInt(colUv))),
      if (colCount > 0) card(AdminKpiCard(label: '图鉴访问次数', value: _fmtInt(colCount))),
      card(AdminKpiCard(label: '鱼种详情访问用户数', value: _fmtInt(detailUv))),
      if (detailCount > 0)
        card(AdminKpiCard(label: '鱼种详情访问次数', value: _fmtInt(detailCount))),
      if (colCount > 0 && colUv > 0)
        card(AdminKpiCard(label: '人均图鉴查看次数', value: (colCount / colUv).toStringAsFixed(2))),
      if (detailCount > 0 && detailUv > 0)
        card(AdminKpiCard(
            label: '人均详情查看次数', value: (detailCount / detailUv).toStringAsFixed(2))),
      card(AdminKpiCard(label: '新增解锁用户数', value: _fmtInt(unlockUv))),
      card(AdminKpiCard(label: '新增解锁次数', value: _fmtInt(unlockCount))),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        const AdminDashSectionTitle('图鉴'),
        _kpi(cards),
        const AdminDashSectionTitle('解锁趋势'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdminSparklineCard(
            title: '新增解锁次数趋势',
            values: _series(rows, 'species_unlock_count'),
            color: AppColors.cyanNav,
          ),
        ),
        AdminAnalyticsDebugPanel(chunks: debugChunks),
      ],
    );
  }
}

num? _nullableNum(Map<String, dynamic>? s, String key) {
  if (s == null || !s.containsKey(key)) return null;
  final v = s[key];
  if (v == null) return null;
  final n = v is num ? v : num.tryParse(v.toString());
  if (n == null || !n.isFinite) return null;
  return n;
}
