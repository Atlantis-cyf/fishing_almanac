import 'dart:async';
import 'dart:math';

import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/analytics/analytics_events.dart';
import 'package:fishing_almanac/analytics/analytics_props.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supabase-backed埋点客户端：用于留存率、上传漏斗、图鉴使用、AI成功率等分析。
///
/// 默认开启（可用 `--dart-define=ENABLE_ANALYTICS=false` 显式关闭），避免多环境配置不一致。
class AnalyticsClient {
  AnalyticsClient({required ApiClient api})  //
      : _api = api,
        _enabled = const bool.fromEnvironment('ENABLE_ANALYTICS', defaultValue: true);

  final ApiClient _api;
  final bool _enabled;

  static const _kAnonId = 'analytics_anon_id_v1';

  /// Web: `1 << 32` breaks `Random.nextInt` (invalid bound on dart2js); keep max ≤ 2^30.
  static int _randomSuffix() => Random().nextInt(1 << 30);

  String? _anonId;
  String? _sessionId;
  String? _userId;
  Map<String, dynamic> _userProfile = const <String, dynamic>{};
  Future<void>? _initFuture;

  Future<void> init() => _initFuture ??= _initInternal();

  Future<void> _initInternal() async {
    final p = await SharedPreferences.getInstance();
    final existing = p.getString(_kAnonId);
    if (existing != null && existing.isNotEmpty) {
      _anonId = existing;
    } else {
      _anonId = 'anon_${DateTime.now().toUtc().millisecondsSinceEpoch}_${_randomSuffix()}';
      await p.setString(_kAnonId, _anonId!);
    }

    _sessionId = 'sess_${DateTime.now().toUtc().millisecondsSinceEpoch}_${_randomSuffix()}';
  }

  String? get anonId => _anonId;
  String? get sessionId => _sessionId;
  String? get userId => _userId;

  void trackFireAndForget(String eventType, {Map<String, dynamic>? properties}) {
    if (!_enabled) return;
    unawaited(trackEvent(eventType, properties: properties));
  }

  /// 统一埋点入口：自动补齐公共字段，页面侧只传业务属性。
  Future<void> trackEvent(String eventType, {Map<String, dynamic>? properties}) {
    return track(eventType, properties: _withCommonProperties(properties));
  }

  /// 页面曝光语义化入口（仍走统一事件上报）。
  Future<void> pageView(String pageName, {Map<String, dynamic>? properties}) {
    return trackEvent(pageName, properties: properties);
  }

  /// 绑定用户画像信息；后续事件自动带上 user_id 与 profile 片段。
  void setUserProfile(String? userId, {Map<String, dynamic>? profile}) {
    _userId = userId;
    _userProfile = Map<String, dynamic>.from(profile ?? const <String, dynamic>{});
  }

  /// 识别反馈预留接口：当前可在任意入口直接调用，不依赖复杂 UI。
  void trackIdentifyFeedback({
    required String requestId,
    String? imageId,
    String? speciesId,
    required bool isCorrect,
  }) {
    trackFireAndForget(
      AnalyticsEvents.identifyFeedback,
      properties: <String, dynamic>{
        AnalyticsProps.requestId: requestId,
        AnalyticsProps.imageId: imageId,
        AnalyticsProps.speciesId: speciesId,
        AnalyticsProps.isCorrect: isCorrect,
      },
    );
  }

  Map<String, dynamic> _withCommonProperties(Map<String, dynamic>? properties) {
    final merged = <String, dynamic>{
      AnalyticsProps.timestamp: DateTime.now().toUtc().toIso8601String(),
      AnalyticsProps.platform: defaultTargetPlatform.name,
      AnalyticsProps.appVersion: const String.fromEnvironment('APP_VERSION', defaultValue: ''),
      AnalyticsProps.userId: _userId,
      ..._userProfile,
      ...?properties,
    };
    merged.removeWhere((key, value) => value == null);
    return merged;
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

