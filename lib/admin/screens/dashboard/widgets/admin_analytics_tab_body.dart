import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/admin/analytics/dashboard_contract.dart';
import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_analytics_filter_bar.dart';
import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

/// 单 Tab 的 Analytics 正文：筛选条 + summary + daily，与后端 query 参数对齐。
///
/// 中文注释：整窗 KPI（如 Collection UV、AI dedup）必须以响应根级的 `data.summary` 为准；
/// `data.daily` 仅作按日/按平台分面，禁止把其中的 UV、dedup 列相加当作整窗指标。
class AdminAnalyticsTabBody extends StatefulWidget {
  const AdminAnalyticsTabBody({
    super.key,
    required this.endpoint,
    required this.showEntryPosition,
  });

  /// 相对 baseUrl 的路径，如 [AdminAnalyticsEndpoints.overview]。
  final String endpoint;

  /// 仅 Upload 漏斗 Tab 为 true，会传 `entry_position` query。
  final bool showEntryPosition;

  @override
  State<AdminAnalyticsTabBody> createState() => _AdminAnalyticsTabBodyState();
}

class _AdminAnalyticsTabBodyState extends State<AdminAnalyticsTabBody> {
  String _timeRange = '7d';
  late final TextEditingController _platformController;
  late final TextEditingController _entryController;
  late final TextEditingController _fromController;
  late final TextEditingController _toController;

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _filter;
  Map<String, dynamic>? _summary;
  List<dynamic> _daily = const [];

  @override
  void initState() {
    super.initState();
    _platformController = TextEditingController();
    _entryController = TextEditingController();
    _fromController = TextEditingController();
    _toController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    _platformController.dispose();
    _entryController.dispose();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildQueryParameters() {
    final q = <String, dynamic>{'time_range': _timeRange};
    final p = _platformController.text.trim();
    if (p.isNotEmpty) q['platform'] = p;
    if (widget.showEntryPosition) {
      final e = _entryController.text.trim();
      if (e.isNotEmpty) q['entry_position'] = e;
    }
    if (_timeRange == 'custom') {
      q['from'] = _fromController.text.trim();
      q['to'] = _toController.text.trim();
    }
    return q;
  }

  void _maybeWarnContractVersion(String? apiVersion) {
    if (apiVersion == null || apiVersion.isEmpty) return;
    if (apiVersion == AdminDashboardContract.contractVersion) return;
    if (!mounted) return;
    final msg =
        '合同版本不一致：API=$apiVersion，前端=${AdminDashboardContract.contractVersion}（口径可能已漂移）';
    debugPrint('[AdminAnalytics] $msg');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
    );
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final res = await api.get<dynamic>(
        widget.endpoint,
        queryParameters: _buildQueryParameters(),
      );
      final root = (res.data as Map?)?.cast<String, dynamic>();
      if (root == null) {
        throw ApiException(message: '响应格式异常：非 JSON 对象');
      }
      _maybeWarnContractVersion(root['contract_version']?.toString());

      final filter = (root['filter'] as Map?)?.cast<String, dynamic>();
      final data = (root['data'] as Map?)?.cast<String, dynamic>();
      final summary = (data?['summary'] as Map?)?.cast<String, dynamic>();
      final daily = data?['daily'];
      final dailyList = daily is List ? daily : <dynamic>[];

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _filter = filter;
        _summary = summary;
        _daily = dailyList;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminAnalyticsFilterBar(
          timeRange: _timeRange,
          onTimeRangeChanged: (v) => setState(() => _timeRange = v),
          platformController: _platformController,
          entryPositionController:
              widget.showEntryPosition ? _entryController : null,
          customFromController: _fromController,
          customToController: _toController,
          onApply: _fetch,
        ),
        if (_filter != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '当前窗口：${_filter!['utc_date_from']} ~ ${_filter!['utc_date_to']}',
              style: AppFont.manrope(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: AppFont.manrope(color: AppColors.error),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _fetch,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _SummarySection(summary: _summary),
                        ),
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              '按日明细（分面用，整窗 UV/dedup 勿对下列求和）',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        if (_daily.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  '暂无日粒度数据',
                                  style: AppFont.manrope(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final row = _daily[index];
                                final map = row is Map
                                    ? Map<String, dynamic>.from(row)
                                    : <String, dynamic>{'value': row};
                                return _DailyTile(row: map);
                              },
                              childCount: _daily.length,
                            ),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }
}

/// Summary KPI：一律来自 `data.summary`。
class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary});

  final Map<String, dynamic>? summary;

  @override
  Widget build(BuildContext context) {
    if (summary == null || summary!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '无 summary 数据',
          style: AppFont.manrope(color: AppColors.onSurfaceVariant),
        ),
      );
    }
    return Card(
      color: AppColors.surfaceContainer,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Summary（整窗 KPI）',
              style: AppFont.manrope(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ...summary!.entries.map((e) => _SummaryEntry(name: e.key, value: e.value)),
          ],
        ),
      ),
    );
  }
}

class _SummaryEntry extends StatelessWidget {
  const _SummaryEntry({required this.name, required this.value});

  final String name;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      final m = Map<String, dynamic>.from(value as Map);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: AppFont.manrope(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.onSurface,
              ),
            ),
            ...m.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  '${e.key}: ${e.value}',
                  style: AppFont.manrope(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$name: $value',
        style: AppFont.manrope(fontSize: 13, color: AppColors.onSurface),
      ),
    );
  }
}

class _DailyTile extends StatelessWidget {
  const _DailyTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final title = row['event_date']?.toString() ??
        row['date']?.toString() ??
        'row';
    final buf = StringBuffer();
    for (final e in row.entries) {
      if (e.key == 'event_date') continue;
      if (buf.isNotEmpty) buf.write('  |  ');
      buf.write('${e.key}=${e.value}');
    }
    return Card(
      color: AppColors.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        dense: true,
        title: Text(
          title,
          style: AppFont.manrope(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Text(
          buf.toString(),
          style: AppFont.manrope(
            fontSize: 11,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
