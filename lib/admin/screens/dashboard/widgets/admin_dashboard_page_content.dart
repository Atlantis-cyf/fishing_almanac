import 'package:flutter/material.dart';

import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_dashboard_charts.dart';
import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_dashboard_debug_panel.dart';
import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_dashboard_layouts.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/theme/app_colors.dart';

String _fmtInt(num v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
String _fmtRate(num v) => (v <= 1 && v >= 0)
    ? '${(v * 100).toStringAsFixed(1)}%'
    : '${v.toStringAsFixed(1)}%';
String _fmtMs(num? v) => v == null ? '-' : '${v.round()} ms';

num? _nullableNum(Map<String, dynamic>? s, String key) {
  if (s == null || !s.containsKey(key)) return null;
  final v = s[key];
  if (v == null) return null;
  final n = v is num ? v : num.tryParse(v.toString());
  if (n == null || !n.isFinite || n <= 0) return null;
  return n;
}

Map<String, dynamic> _mergeOverview(
  Map<String, dynamic>? overview,
  Map<String, dynamic>? collection,
  Map<String, dynamic>? upload,
) {
  final m = Map<String, dynamic>.from(overview ?? const {});
  final c = collection ?? const {};
  final u = upload ?? const {};
  m['species_unlock_count'] = readSummaryNum(c, 'species_unlock_count');
  m['collection_view_uv'] = readSummaryNum(c, 'collection_view_uv');
  m['species_detail_view_uv'] = readSummaryNum(c, 'species_detail_view_uv');
  m['upload_click_uv'] = readSummaryNum(u, 'upload_click_uv');
  m['upload_success_uv'] = readSummaryNum(u, 'upload_success_uv');
  return m;
}

List<Map<String, dynamic>> _overviewDaily(
    List<dynamic> overviewRows, List<dynamic> collectionRows) {
  final bucket = <String, Map<String, dynamic>>{};
  void ensure(String d) => bucket.putIfAbsent(d, () => {'event_date': d});

  for (final x in overviewRows) {
    if (x is! Map) continue;
    final r = Map<String, dynamic>.from(x);
    final d = r['event_date']?.toString() ?? '';
    if (d.isEmpty) continue;
    ensure(d);
    final t = bucket[d]!;
    for (final k in const [
      'active_users_uv',
      'upload_success_count',
      'ai_identify_result_count',
      'upload_click_count',
      'app_launch_count',
      'collection_view_count',
    ]) {
      t[k] = readSummaryNum(t, k) + readSummaryNum(r, k);
    }
  }
  for (final x in collectionRows) {
    if (x is! Map) continue;
    final r = Map<String, dynamic>.from(x);
    final d = r['event_date']?.toString() ?? '';
    if (d.isEmpty) continue;
    ensure(d);
    final t = bucket[d]!;
    t['species_unlock_count'] = readSummaryNum(t, 'species_unlock_count') +
        readSummaryNum(r, 'species_unlock_count');
  }
  final keys = bucket.keys.toList()..sort();
  return [for (final k in keys) bucket[k]!];
}

List<double> _series(List<Map<String, dynamic>> rows, String key) =>
    [for (final r in rows) readSummaryNum(r, key).toDouble()];

Map<String, num> _entryMix(Map<String, dynamic>? summary) {
  final raw = summary?['entry_position_click_mix'];
  if (raw is! Map) return {};
  final m = Map<String, dynamic>.from(raw);
  final out = <String, num>{};
  m.forEach((k, _) => out[k] = readSummaryNum(m, k));
  return out;
}

Map<String, int> _failDist(Map<String, dynamic>? summary) {
  final raw = summary?['fail_reason_breakdown'];
  if (raw is! Map) return {};
  final m = Map<String, dynamic>.from(raw);
  final out = <String, int>{};
  m.forEach((k, _) => out[k] = readSummaryNum(m, k).round());
  return out;
}

class AdminDashboardPageContent extends StatelessWidget {
  const AdminDashboardPageContent({
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
    final width = cardWidth.clamp(148.0, 520.0);
    Widget card(Widget child) => SizedBox(width: width, child: child);
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

  Widget _kpi(List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 12, runSpacing: 12, children: children),
      );

  Widget _overview(Widget Function(Widget) card) {
    final merged = _mergeOverview(
      summary,
      extraSummaries[AdminAnalyticsEndpoints.collectionGrowth],
      extraSummaries[AdminAnalyticsEndpoints.uploadFunnel],
    );
    final dailyRows = _overviewDaily(daily,
        extraDailies[AdminAnalyticsEndpoints.collectionGrowth] ?? const []);
    final funnel = <({String label, num value})>[
      (label: 'DAU', value: readSummaryNum(merged, 'active_users_uv')),
      (
        label: 'upload_click',
        value: readSummaryNum(merged, 'upload_click_count')
      ),
      (
        label: 'upload_success',
        value: readSummaryNum(merged, 'upload_success_count')
      ),
      (
        label: 'ai_success',
        value: readSummaryNum(merged, 'ai_identify_result_count')
      ),
      (
        label: 'species_unlock',
        value: readSummaryNum(merged, 'species_unlock_count')
      ),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        const AdminDashSectionTitle('概览 KPI'),
        _kpi([
          card(AdminKpiCard(
              label: 'DAU',
              value: _fmtInt(readSummaryNum(merged, 'active_users_uv')))),
          card(AdminKpiCard(
              label: '上传用户数',
              value: _fmtInt(readSummaryNum(merged, 'upload_click_uv')))),
          card(AdminKpiCard(
              label: '上传成功数',
              value: _fmtInt(readSummaryNum(merged, 'upload_success_count')))),
          card(AdminKpiCard(
              label: 'AI识别成功数',
              value:
                  _fmtInt(readSummaryNum(merged, 'ai_identify_result_count')))),
          card(AdminKpiCard(
              label: '新解锁数',
              value: _fmtInt(readSummaryNum(merged, 'species_unlock_count')))),
          card(AdminKpiCard(
              label: '图鉴访问用户数',
              value: _fmtInt(readSummaryNum(merged, 'collection_view_uv')))),
          card(AdminKpiCard(
              label: '上传转化率',
              value:
                  _fmtRate(readSummaryNum(merged, 'upload_conversion_rate')))),
          card(AdminKpiCard(
              label: '识别成功率',
              value:
                  _fmtRate(readSummaryNum(merged, 'identify_success_rate')))),
        ]),
        AdminOverviewCoreFunnel(steps: funnel),
        const AdminDashSectionTitle('近 7/14 天趋势'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              AdminSparklineCard(
                  title: 'DAU',
                  values: _series(dailyRows, 'active_users_uv'),
                  color: AppColors.cyanNav),
              const SizedBox(height: 12),
              AdminSparklineCard(
                  title: '上传成功次数',
                  values: _series(dailyRows, 'upload_success_count'),
                  color: AppColors.secondaryFixed),
              const SizedBox(height: 12),
              AdminSparklineCard(
                  title: 'AI识别成功次数',
                  values: _series(dailyRows, 'ai_identify_result_count'),
                  color: AppColors.primaryContainer),
              const SizedBox(height: 12),
              AdminSparklineCard(
                  title: '解锁次数',
                  values: _series(dailyRows, 'species_unlock_count'),
                  color: const Color(0xFFfb923c)),
            ],
          ),
        ),
        AdminAnalyticsDebugPanel(chunks: debugChunks),
      ],
    );
  }

  Widget _upload(Widget Function(Widget) card) {
    final rows = [
      for (final x in daily)
        if (x is Map) Map<String, dynamic>.from(x)
    ]..sort((a, b) => '${a['event_date']}'.compareTo('${b['event_date']}'));
    final mix = _entryMix(summary);
    num cam = 0, alb = 0, oth = 0;
    mix.forEach((k, v) {
      final key = k.toLowerCase();
      if (key.contains('camera'))
        cam += v;
      else if (key.contains('album'))
        alb += v;
      else
        oth += v;
    });

    final clickUv = readSummaryNum(summary, 'upload_click_uv');
    final successUv = readSummaryNum(summary, 'upload_success_uv');
    final uvRate = clickUv > 0 ? successUv / clickUv : 0;

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        const AdminDashSectionTitle('上传看板'),
        _kpi([
          card(AdminKpiCard(label: '上传点击人数', value: _fmtInt(clickUv))),
          card(AdminKpiCard(label: '上传成功人数', value: _fmtInt(successUv))),
          card(AdminKpiCard(label: '上传成功率', value: _fmtRate(uvRate))),
          card(AdminKpiCard(
              label: '平均上传耗时',
              value: _fmtMs(_nullableNum(summary, 'upload_avg_duration_ms')))),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdminMixBar(
            label: 'camera / album 占比',
            segments: [
              (name: 'camera', value: cam, color: AppColors.cyanNav),
              (name: 'album', value: alb, color: AppColors.secondaryFixed),
              (
                name: 'other',
                value: oth,
                color: AppColors.surfaceContainerHighest
              ),
            ],
          ),
        ),
        const AdminDashSectionTitle('近 7/14 天上传趋势'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdminSparklineCard(
              title: '上传成功次数',
              values: _series(rows, 'upload_success_count'),
              color: AppColors.primaryContainer),
        ),
        AdminAnalyticsDebugPanel(chunks: debugChunks),
      ],
    );
  }

  Widget _ai(Widget Function(Widget) card) {
    final rows = [
      for (final x in daily)
        if (x is Map) Map<String, dynamic>.from(x)
    ]..sort((a, b) => '${a['event_date']}'.compareTo('${b['event_date']}'));
    final conf = _nullableNum(summary, 'identify_confidence_avg');
    final dist = _failDist(summary).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        const AdminDashSectionTitle('AI 看板'),
        _kpi([
          card(AdminKpiCard(
              label: '识别发起次数',
              value: _fmtInt(readSummaryNum(summary, 'identify_start_count')))),
          card(AdminKpiCard(
              label: '识别成功次数',
              value:
                  _fmtInt(readSummaryNum(summary, 'identify_result_count')))),
          card(AdminKpiCard(
              label: '识别失败次数',
              value: _fmtInt(readSummaryNum(summary, 'identify_fail_count')))),
          card(AdminKpiCard(
              label: '识别成功率',
              value:
                  _fmtRate(readSummaryNum(summary, 'identify_success_rate')))),
          card(AdminKpiCard(
              label: '平均 latency',
              value: _fmtMs(_nullableNum(summary, 'identify_latency_avg_ms')))),
          card(AdminKpiCard(
              label: '平均 confidence',
              value: conf == null ? '-' : conf.toStringAsFixed(3))),
        ]),
        const AdminDashSectionTitle('失败原因分布'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: dist.isEmpty
              ? Card(
                  color: AppColors.surfaceContainerLow,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无失败原因数据（空状态）'),
                  ),
                )
              : Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in dist)
                    Chip(label: Text('${e.key}: ${e.value}'))
                ]),
        ),
        const AdminDashSectionTitle('近 7/14 天趋势'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              AdminSparklineCard(
                  title: '发起次数',
                  values: _series(rows, 'identify_start_count'),
                  color: AppColors.cyanNav),
              const SizedBox(height: 12),
              AdminSparklineCard(
                  title: '成功次数',
                  values: _series(rows, 'identify_result_count'),
                  color: AppColors.secondaryFixed),
              const SizedBox(height: 12),
              AdminSparklineCard(
                  title: '失败次数',
                  values: _series(rows, 'identify_fail_count'),
                  color: const Color(0xFFfb7185)),
            ],
          ),
        ),
        AdminAnalyticsDebugPanel(chunks: debugChunks),
      ],
    );
  }

  Widget _collection(Widget Function(Widget) card) {
    final merged = Map<String, dynamic>.from(summary ?? const {});
    final ov = extraSummaries[AdminAnalyticsEndpoints.overview] ?? const {};
    merged['overview_collection_view_count'] =
        readSummaryNum(ov, 'collection_view_count');

    final colUv = readSummaryNum(merged, 'collection_view_uv');
    final detailUv = readSummaryNum(merged, 'species_detail_view_uv');
    final viewCount = readSummaryNum(merged, 'overview_collection_view_count');
    final perCollection = colUv > 0 ? viewCount / colUv : 0;

    final rows = [
      for (final x in daily)
        if (x is Map) Map<String, dynamic>.from(x)
    ]..sort((a, b) => '${a['event_date']}'.compareTo('${b['event_date']}'));

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        const AdminDashSectionTitle('图鉴看板'),
        _kpi([
          card(AdminKpiCard(label: '图鉴访问用户数', value: _fmtInt(colUv))),
          card(AdminKpiCard(label: '鱼种详情访问用户数', value: _fmtInt(detailUv))),
          card(AdminKpiCard(
              label: '人均图鉴查看次数',
              value:
                  perCollection > 0 ? perCollection.toStringAsFixed(2) : '-')),
          card(const AdminKpiCard(
              label: '人均详情查看次数', value: '-', subtitle: '缺少详情总次数字段，当前为占位态')),
          card(AdminKpiCard(
              label: '解锁次数',
              value: _fmtInt(readSummaryNum(merged, 'species_unlock_count')))),
        ]),
        const AdminDashSectionTitle('解锁趋势'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _series(rows, 'species_unlock_count').every((e) => e == 0)
              ? Card(
                  color: AppColors.surfaceContainerLow,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('数据不足，当前为空状态'),
                  ),
                )
              : AdminSparklineCard(
                  title: '解锁次数',
                  values: _series(rows, 'species_unlock_count'),
                  color: AppColors.cyanNav),
        ),
        AdminAnalyticsDebugPanel(chunks: debugChunks),
      ],
    );
  }
}
