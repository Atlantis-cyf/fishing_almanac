import 'package:flutter/foundation.dart' show kIsWeb;

import 'api_loopback_rewriter_stub.dart'
    if (dart.library.io) 'api_loopback_rewriter_io.dart' as loopback;

/// 后端基址配置。
///
/// 构建时注入（推荐联调 / CI）：
/// ```bash
/// flutter run --dart-define=API_BASE_URL=https://api.example.com
/// ```
///
/// Web 未设置时默认 [Uri.base.origin]（与当前页面同源，适配 Vercel 多域名）；其它平台默认本地占位。
///
/// **Android 模拟器**：若基址为 `127.0.0.1` 或 `localhost`，会自动改为 `10.0.2.2`，
/// 否则请求会打到模拟器自身导致超时。真机请显式传入电脑局域网 IP。
abstract final class ApiConfig {
  static const String _defineKey = 'API_BASE_URL';

  /// 来自 `--dart-define=API_BASE_URL=...`；为空则使用 [defaultBaseUrl]。
  ///
  /// 在 Android 上对环回主机名做模拟器友好改写。
  static String get baseUrl {
    const fromDefine = String.fromEnvironment(_defineKey);
    final raw = fromDefine.isNotEmpty
        ? fromDefine
        : (kIsWeb ? Uri.base.origin : defaultBaseUrl);
    return loopback.applyAndroidEmulatorLoopbackRewrite(_trimTrailingSlash(raw));
  }

  /// 开发默认基址；可按团队约定修改。
  static const String defaultBaseUrl = 'http://127.0.0.1:8080';

  static String _trimTrailingSlash(String u) {
    if (u.endsWith('/')) return u.substring(0, u.length - 1);
    return u;
  }
}

/// 鉴权接口路径（可按后端调整 `--dart-define`）。
abstract final class AuthEndpoints {
  static const String login = String.fromEnvironment(
    'AUTH_LOGIN_PATH',
    defaultValue: '/auth/login',
  );
  static const String register = String.fromEnvironment(
    'AUTH_REGISTER_PATH',
    defaultValue: '/auth/register',
  );
}

/// 当前用户资料：`GET` 拉取、`PATCH` 更新展示名（Bearer）。
abstract final class UserMeEndpoints {
  static const String path = String.fromEnvironment(
    'USER_ME_PATH',
    defaultValue: '/me',
  );
}

/// 鱼获列表 GET（query：`limit`、`after_occurred_at_ms`/`after_id` 或 `page`、`scientific_name`/`species_id`；兼容旧 `species_zh`）。
abstract final class CatchListEndpoints {
  static const String listPath = String.fromEnvironment(
    'CATCH_LIST_PATH',
    defaultValue: '/v1/catches',
  );

  static const int pageSize = int.fromEnvironment(
    'CATCH_LIST_LIMIT',
    defaultValue: 20,
  );

  /// 为 true 时使用 `page` 分页；否则使用游标 query（`after_occurred_at_ms` + `after_id`）。
  static const bool usePageParam = bool.fromEnvironment(
    'CATCH_LIST_USE_PAGE_PARAM',
    defaultValue: false,
  );

  /// 为 true 时优先传 `species_id`（见 [RemoteCatchRepository] 内置映射），否则传 `scientific_name`。
  static const bool useSpeciesId = bool.fromEnvironment(
    'CATCH_LIST_USE_SPECIES_ID',
    defaultValue: false,
  );
}

/// 鱼获发布：multipart 直传（字段名 snake_case，与 PR-4 DTO 对齐）。
abstract final class CatchPublishEndpoints {
  static const String createPath = String.fromEnvironment(
    'CATCH_PUBLISH_PATH',
    defaultValue: '/v1/catches',
  );

  /// 更新 URL 前缀，与 [createPath] 相同时 PUT `/v1/catches/{id}`。
  static const String detailBase = String.fromEnvironment(
    'CATCH_CATCH_DETAIL_BASE',
    defaultValue: '/v1/catches',
  );

  static String updatePath(String id) {
    final b = detailBase.endsWith('/') ? detailBase.substring(0, detailBase.length - 1) : detailBase;
    return '$b/$id';
  }

  /// multipart 中图片字段名。
  static const String imageField = String.fromEnvironment(
    'CATCH_PUBLISH_IMAGE_FIELD',
    defaultValue: 'image',
  );
}

/// 鱼种识别（multipart 图片或 JSON `image_url`，走 [ApiClient] + Bearer）。
abstract final class SpeciesIdentifyEndpoints {
  static const String path = String.fromEnvironment(
    'SPECIES_IDENTIFY_PATH',
    defaultValue: '/v1/species/identify',
  );

  static const String imageField = String.fromEnvironment(
    'SPECIES_IDENTIFY_IMAGE_FIELD',
    defaultValue: 'image',
  );
}

/// 发布前图片处理与相册压缩质量（均可 `--dart-define`）。
abstract final class CatchPublishImageConfig {
  /// 长边上限（像素），超过则等比缩小。
  static const int maxEdge = int.fromEnvironment(
    'CATCH_IMAGE_MAX_EDGE',
    defaultValue: 2048,
  );

  /// JPEG 质量 1–100。
  static const int jpegQuality = int.fromEnvironment(
    'CATCH_PUBLISH_JPEG_QUALITY',
    defaultValue: 85,
  );

  /// 为 true 时跳过重编码，原样上传（仍走 multipart）。
  static const bool skipReencode = bool.fromEnvironment(
    'CATCH_PUBLISH_SKIP_IMAGE_REENCODE',
    defaultValue: false,
  );

  /// [ImagePicker] `imageQuality` 参数（0–100）。
  static const int pickerQuality = int.fromEnvironment(
    'CATCH_IMAGE_PICKER_QUALITY',
    defaultValue: 85,
  );
}

/// 埋点（analytics events）
abstract final class AnalyticsEndpoints {
  static const String events = String.fromEnvironment(
    'ANALYTICS_EVENTS_PATH',
    defaultValue: '/v1/analytics/events',
  );
}

/// 物种目录（服务端动态拉取）。
abstract final class SpeciesCatalogEndpoints {
  static const String list = String.fromEnvironment(
    'SPECIES_CATALOG_LIST_PATH',
    defaultValue: '/v1/species/catalog',
  );

  static const String create = String.fromEnvironment(
    'SPECIES_CATALOG_CREATE_PATH',
    defaultValue: '/v1/species/catalog',
  );

  static const String search = String.fromEnvironment(
    'SPECIES_CATALOG_SEARCH_PATH',
    defaultValue: '/v1/species/search',
  );
}

/// 物种后台管理 API（仅管理员）。
abstract final class AdminSpeciesEndpoints {
  static const String list = String.fromEnvironment(
    'ADMIN_SPECIES_LIST_PATH',
    defaultValue: '/v1/admin/species',
  );

  static const String mergePreview = String.fromEnvironment(
    'ADMIN_SPECIES_MERGE_PREVIEW_PATH',
    defaultValue: '/v1/admin/species/merge/preview',
  );

  static const String merge = String.fromEnvironment(
    'ADMIN_SPECIES_MERGE_PATH',
    defaultValue: '/v1/admin/species/merge',
  );

  static const String snapshots = String.fromEnvironment(
    'ADMIN_SPECIES_SNAPSHOTS_PATH',
    defaultValue: '/v1/admin/species/snapshots',
  );

  static const String auditLogs = String.fromEnvironment(
    'ADMIN_SPECIES_AUDIT_LOGS_PATH',
    defaultValue: '/v1/admin/species/audit-logs',
  );

  static String detail(int id) => '$list/$id';
  static String image(int id) => '$list/$id/image';
  static String aliases(int id) => '$list/$id/aliases';
  static String replaceAliases(int id) => '$list/$id/aliases/replace';
  static String aliasById(int id, int aliasId) => '$list/$id/aliases/$aliasId';
  static String restoreSnapshot(String snapshotId) => '$snapshots/$snapshotId/restore';
}

/// 图鉴相关 API。
abstract final class EncyclopediaEndpoints {
  /// 当前进度：已解锁鱼种数量 / 全图鉴物种库数量（目前后端 mock 650）。
  static const String stats = String.fromEnvironment(
    'ENCYCLOPEDIA_STATS_PATH',
    defaultValue: '/v1/encyclopedia/stats',
  );

  /// 用户已解锁的鱼种及其上传鱼获数量。
  static const String mySpecies = String.fromEnvironment(
    'ENCYCLOPEDIA_MY_SPECIES_PATH',
    defaultValue: '/v1/encyclopedia/my_species',
  );
}
