import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/admin/analytics/dashboard_contract.dart';
import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_analytics_filter_bar.dart';
import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_dashboard_business_content.dart';
import 'package:fishing_almanac/admin/screens/dashboard/widgets/admin_dashboard_layouts.dart';
import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

class AdminAnalyticsTabBody extends StatefulWidget {
  const AdminAnalyticsTabBody({
    super.key,
    required this.endpoint,
    required this.showEntryPosition,
    required this.mode,
  });

  final String endpoint;
  final bool showEntryPosition;
  final AnalyticsDashboardMode mode;

  @override
  State<AdminAnalyticsTabBody> createState() => _AdminAnalyticsTabBodyState();
}

class _AdminAnalyticsTabBodyState extends State<AdminAnalyticsTabBody> {
  String _timeRange = '7d';
  String? _platform;
  String? _entryPosition;
  late final TextEditingController _fromController;
  late final TextEditingController _toController;

  bool _loading = false;
  String? _error;

  Map<String, dynamic>? _filter;
  Map<String, dynamic>? _summary;
  List<dynamic> _daily = const [];

  final Map<String, Map<String, dynamic>?> _extraSummaries = {};
  final Map<String, List<dynamic>> _extraDailies = {};
  final Map<String, Object?> _debugRaw = {};
  List<String> _platformOptions = const [];
  List<String> _entryPositionOptions = const [];

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController();
    _toController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildQueryParameters() {
    final q = <String, dynamic>{'time_range': _timeRange};
    final p = _platform?.trim() ?? '';
    if (p.isNotEmpty) q['platform'] = p;
    if (widget.showEntryPosition) {
      final e = _entryPosition?.trim() ?? '';
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

  List<String> _companionEndpoints() {
    switch (widget.mode) {
      case AnalyticsDashboardMode.overview:
        return [
          AdminAnalyticsEndpoints.collectionGrowth,
          AdminAnalyticsEndpoints.uploadFunnel,
        ];
      case AnalyticsDashboardMode.collectionGrowth:
        return [AdminAnalyticsEndpoints.overview];
      case AnalyticsDashboardMode.uploadFunnel:
      case AnalyticsDashboardMode.aiIdentify:
        return const [];
    }
  }

  Future<Map<String, dynamic>> _fetchEndpoint(
    ApiClient api,
    String endpoint,
    Map<String, dynamic> qp,
  ) async {
    final res = await api.get<dynamic>(endpoint, queryParameters: qp);
    final root = (res.data as Map?)?.cast<String, dynamic>();
    if (root == null) {
      throw ApiException(message: '响应格式异常：$endpoint 非 JSON 对象');
    }
    _maybeWarnContractVersion(root['contract_version']?.toString());
    return root;
  }

  List<String> _sortedSet(Iterable<String> items) {
    final out = items
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim())
        .toSet()
        .toList()
      ..sort();
    return out;
  }

  void _deriveFilterOptions({
    required List<dynamic> primaryDaily,
    required Map<String, List<dynamic>> extraDailies,
  }) {
    final platformSet = <String>{};
    final entrySet = <String>{};

    void ingestDaily(List<dynamic> rows) {
      for (final x in rows) {
        if (x is! Map) continue;
        final row = Map<String, dynamic>.from(x);
        final p = row['platform']?.toString();
        if (p != null && p.trim().isNotEmpty) platformSet.add(p.trim());

        final e = row['entry_position_bucket']?.toString() ??
            row['entry_position']?.toString();
        if (e != null && e.trim().isNotEmpty) {
          final t = e.trim();
          if (t != '__rollup__' && t != '__all__') entrySet.add(t);
        }
      }
    }

    ingestDaily(primaryDaily);
    for (final d in extraDailies.values) {
      ingestDaily(d);
    }
    if (_platform != null && _platform!.trim().isNotEmpty) {
      platformSet.add(_platform!.trim());
    }
    if (_entryPosition != null && _entryPosition!.trim().isNotEmpty) {
      entrySet.add(_entryPosition!.trim());
    }

    _platformOptions = _sortedSet(platformSet);
    _entryPositionOptions = _sortedSet(entrySet);
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final qp = _buildQueryParameters();

      final root = await _fetchEndpoint(api, widget.endpoint, qp);
      final filter = (root['filter'] as Map?)?.cast<String, dynamic>();
      final data = (root['data'] as Map?)?.cast<String, dynamic>();
      final summary = (data?['summary'] as Map?)?.cast<String, dynamic>();
      final daily = data?['daily'];
      final dailyList = daily is List ? daily : <dynamic>[];

      final extraSummaries = <String, Map<String, dynamic>?>{};
      final extraDailies = <String, List<dynamic>>{};
      final debugRaw = <String, Object?>{widget.endpoint: root};

      for (final ep in _companionEndpoints()) {
        final r = await _fetchEndpoint(api, ep, qp);
        debugRaw[ep] = r;
        final d = (r['data'] as Map?)?.cast<String, dynamic>();
        extraSummaries[ep] = (d?['summary'] as Map?)?.cast<String, dynamic>();
        final x = d?['daily'];
        extraDailies[ep] = x is List ? x : <dynamic>[];
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _filter = filter;
        _summary = summary;
        _daily = dailyList;
        _extraSummaries
          ..clear()
          ..addAll(extraSummaries);
        _extraDailies
          ..clear()
          ..addAll(extraDailies);
        _debugRaw
          ..clear()
          ..addAll(debugRaw);
        _deriveFilterOptions(
            primaryDaily: dailyList, extraDailies: extraDailies);
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
          platformValue: _platform,
          platformOptions: _platformOptions,
          onPlatformChanged: (v) => setState(() => _platform = v),
          entryPositionValue: widget.showEntryPosition ? _entryPosition : null,
          onEntryPositionChanged: widget.showEntryPosition
              ? (v) => setState(() => _entryPosition = v)
              : null,
          entryPositionOptions:
              widget.showEntryPosition ? _entryPositionOptions : const [],
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
                                onPressed: _fetch, child: const Text('重试')),
                          ],
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final innerW = constraints.maxWidth - 32;
                        final cardW = ((innerW - 12) / 2).clamp(148.0, 520.0);
                        final empty =
                            isSummaryEffectivelyEmpty(widget.mode, _summary);
                        return Column(
                          children: [
                            if (empty) const AdminAnalyticsEmptyHint(),
                            Expanded(
                              child: AdminDashboardBusinessContent(
                                mode: widget.mode,
                                cardWidth: cardW,
                                summary: _summary,
                                daily: _daily,
                                extraSummaries: _extraSummaries,
                                extraDailies: _extraDailies,
                                debugChunks: _debugRaw,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
