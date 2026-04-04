import 'dart:async';
import 'dart:math';

import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supabase-backed埋点客户端：用于留存率、上传漏斗、图鉴使用、AI成功率等分析。
///
/// 默认关闭（`--dart-define=ENABLE_ANALYTICS=true` 才会真正上报），避免 flutter test / 未配置环境时打扰。
class AnalyticsClient {
  AnalyticsClient({required ApiClient api})  //
      : _api = api,
        _enabled = const bool.fromEnvironment('ENABLE_ANALYTICS', defaultValue: false);

  final ApiClient _api;
  final bool _enabled;

  static const _kAnonId = 'analytics_anon_id_v1';

  String? _anonId;
  String? _sessionId;
  Future<void>? _initFuture;

  Future<void> init() => _initFuture ??= _initInternal();

  Future<void> _initInternal() async {
    final p = await SharedPreferences.getInstance();
    final existing = p.getString(_kAnonId);
    if (existing != null && existing.isNotEmpty) {
      _anonId = existing;
    } else {
      _anonId = 'anon_${DateTime.now().toUtc().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
      await p.setString(_kAnonId, _anonId!);
    }

    _sessionId = 'sess_${DateTime.now().toUtc().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
  }

  String? get anonId => _anonId;
  String? get sessionId => _sessionId;

  void trackFireAndForget(String eventType, {Map<String, dynamic>? properties}) {
    if (!_enabled) return;
    unawaited(track(eventType, properties: properties));
  }

  Future<void> track(String eventType, {Map<String, dynamic>? properties}) async {
    if (!_enabled) return;
    await init();
    final anonId = _anonId;
    final sessionId = _sessionId;
    if (anonId == null || sessionId == null) return;

    try {
      await _api.post<dynamic>(
        AnalyticsEndpoints.events,
        data: <String, dynamic>{
          'events': <Map<String, dynamic>>[
            <String, dynamic>{
              'event_type': eventType,
              'anon_id': anonId,
              'session_id': sessionId,
              'properties': properties ?? <String, dynamic>{},
            }
          ],
        },
      );
    } catch (e, st) {
      // 埋点不应影响主流程：只做日志，不向上抛出。
      debugPrint('Analytics track failed: $e\n$st');
    }
  }
}

