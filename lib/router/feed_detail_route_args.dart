import 'package:go_router/go_router.dart';

import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/feed_detail_extra.dart';

/// [FeedDetailScreen] 路由参数：query、path 与 [GoRouterState.extra] 合并。
///
/// **优先级**（与 [FeedDetailExtra] 并存）：
/// - `initialIndex`：`extra` 为 [FeedDetailExtra] 时用其 [FeedDetailExtra.initialIndex]；
///   否则 `extra` 为 `int` 时用该值；否则来自 query `index` / `i`（默认 0）。
/// - `speciesScientificName`：`extra` 为 [FeedDetailExtra] 且 [FeedDetailExtra.speciesScientificName] 非空时用之；
///   否则 path 参数 `scientificName`（`/feed-detail/…` 一段，需 URL 编码）；
///   否则 query `scientific_name` / `scientificName`，或兼容旧键 `species` / `species_zh` / `speciesFilterZh`（经图鉴解析为学名）。
typedef FeedDetailRouteArgs = ({int initialIndex, String? speciesScientificName, String? anchorCatchId});

String? _resolveSpeciesFromUriSegment(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.contains('%')) {
    try {
      s = Uri.decodeComponent(s).trim();
    } catch (_) {
      // keep s
    }
  }
  if (s.isEmpty) return null;
  return SpeciesCatalog.resolveScientificNameFromUserInput(s);
}

FeedDetailRouteArgs parseFeedDetailRouteArgsRaw({
  required Uri uri,
  Map<String, String> pathParameters = const {},
  Object? extra,
}) {
  final q = uri.queryParameters;
  final qIndexRaw = q['index'] ?? q['i'] ?? '';
  var qIndex = int.tryParse(qIndexRaw) ?? 0;
  if (qIndex < 0) qIndex = 0;

  final qSpeciesRaw = (q['scientific_name'] ?? q['scientificName'] ?? q['species'] ?? q['species_zh'] ?? q['speciesFilterZh'])
      ?.trim();
  final qSpecies = (qSpeciesRaw != null && qSpeciesRaw.isEmpty) ? null : qSpeciesRaw;

  String? qCatchId = q['catch_id'] ?? q['catchId'];
  qCatchId = qCatchId?.trim();
  if (qCatchId != null && qCatchId.isEmpty) qCatchId = null;

  final pathRaw = pathParameters['scientificName'];
  final pathResolved = _resolveSpeciesFromUriSegment(pathRaw);
  final queryResolved = _resolveSpeciesFromUriSegment(qSpecies);

  final speciesFromUri = pathResolved ?? queryResolved;

  if (extra is FeedDetailExtra) {
    final fromExtra = extra.speciesScientificName;
    final merged = (fromExtra != null && fromExtra.isNotEmpty)
        ? SpeciesCatalog.resolveScientificNameFromUserInput(fromExtra)
        : speciesFromUri;
    return (
      initialIndex: extra.initialIndex,
      speciesScientificName: merged,
      anchorCatchId: extra.anchorCatchId ?? qCatchId,
    );
  }
  if (extra is int) {
    return (initialIndex: extra, speciesScientificName: speciesFromUri, anchorCatchId: qCatchId);
  }

  return (initialIndex: qIndex, speciesScientificName: speciesFromUri, anchorCatchId: qCatchId);
}

FeedDetailRouteArgs parseFeedDetailRouteArgs(GoRouterState state) {
  return parseFeedDetailRouteArgsRaw(
    uri: state.uri,
    pathParameters: state.pathParameters,
    extra: state.extra,
  );
}

/// `?redirect=` 解码后的值（已由 [Uri] 解码一次）：校验后供 `context.go`。
String? sanitizePostLoginRedirectQuery(String? value) {
  if (value == null || value.isEmpty) return null;
  final t = value.trim();
  if (!t.startsWith('/') || t.startsWith('//')) return null;
  if (t.contains('..')) return null;
  return t;
}
