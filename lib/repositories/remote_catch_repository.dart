import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/api/catch_publish_image_prepare.dart';
import 'package:fishing_almanac/api/catch_publish_multipart.dart';
import 'package:fishing_almanac/api/dto/catch_list_page_parser.dart';
import 'package:fishing_almanac/api/dto/catch_record_dto.dart';
import 'package:fishing_almanac/api/mappers/catch_record_mapper.dart';
import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';
import 'package:fishing_almanac/models/published_catch.dart';
import 'package:fishing_almanac/repositories/catch_feed_page.dart';
import 'package:fishing_almanac/repositories/catch_repository.dart';
import 'package:fishing_almanac/repositories/catch_timeline_cursor.dart';

/// 远程列表 + multipart 发布。
///
/// 内置**短时缓存**（[_cacheTtl]），同一请求在 TTL 内直接返回内存数据，
/// 页面切换（首页 ↔ 图鉴 ↔ 信息流）不再每次打网络。
/// 发布/删除等写操作会 [_invalidateCache] 强制下次走网络。
class RemoteCatchRepository extends CatchRepository {
  RemoteCatchRepository({
    required ApiClient api,
    required AuthSession authSession,
  })  : _api = api,
        _auth = authSession;

  final ApiClient _api;
  final AuthSession _auth;

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static const Map<int, String> _speciesIdToScientificName = {
    1: 'Thunnus thynnus',
    2: 'Coryphaena hippurus',
    3: 'Lutjanus campechanus',
    4: 'Anyperodon leucogrammicus',
    5: 'Morone saxatilis',
  };

  // --------------- cache ---------------
  static const Duration _cacheTtl = Duration(seconds: 30);

  final Map<String, _CacheEntry<CatchFeedPage>> _pageCache = {};

  String _cacheKey(String? scientificName, int? speciesId, CatchTimelineCursor? cursor) {
    return '${scientificName ?? ''}|${speciesId ?? ''}|${cursor?.occurredAtMs ?? ''}|${cursor?.id ?? ''}|${cursor?.page ?? ''}';
  }

  void _invalidateCache() => _pageCache.clear();
  // --------------- /cache ---------------

  int _mutationGen = 0;

  @override
  int get dataGeneration => _mutationGen;

  @override
  bool get usesRemoteTimeline => true;

  void _bumpAfterMutation() {
    _invalidateCache();
    _mutationGen++;
    notifyListeners();
  }

  Future<CatchFeedPage> _fetch({
    required String? scientificName,
    required int? speciesId,
    CatchTimelineCursor? cursor,
  }) async {
    if (!_auth.isReady || !_auth.isLoggedIn) {
      return const CatchFeedPage(items: [], hasMore: false);
    }

    final key = _cacheKey(scientificName, speciesId, cursor);
    final cached = _pageCache[key];
    if (cached != null && !cached.isExpired) return cached.value;

    final limit = CatchListEndpoints.pageSize;
    final qp = <String, dynamic>{'limit': limit};

    if (speciesId != null) {
      qp['species_id'] = speciesId;
    } else if (scientificName != null && scientificName.isNotEmpty) {
      qp['scientific_name'] = scientificName;
    }

    if (CatchListEndpoints.usePageParam) {
      qp['page'] = cursor?.page ?? 1;
    } else {
      if (cursor?.occurredAtMs != null) {
        qp['after_occurred_at_ms'] = cursor!.occurredAtMs;
        if (cursor.id != null && cursor.id!.isNotEmpty) {
          qp['after_id'] = cursor.id;
        }
      }
    }

    final res = await _api.get<dynamic>(CatchListEndpoints.listPath, queryParameters: qp);
    var page = CatchListPageParser.parse(res.data, limit: limit);
    page = _syntheticPageCursor(page, cursor);
    _pageCache[key] = _CacheEntry(page);
    return page;
  }

  CatchFeedPage _syntheticPageCursor(CatchFeedPage page, CatchTimelineCursor? requestCursor) {
    if (!CatchListEndpoints.usePageParam || !page.hasMore) return page;
    if (page.nextCursor != null) return page;
    if (page.items.isEmpty) return page;
    final nextPage = (requestCursor?.page ?? 1) + 1;
    return CatchFeedPage(
      items: page.items,
      hasMore: page.hasMore,
      nextCursor: CatchTimelineCursor(page: nextPage),
    );
  }

  @override
  Future<CatchFeedPage> timelineHome({CatchTimelineCursor? cursor}) async {
    return _fetch(scientificName: null, speciesId: null, cursor: cursor);
  }

  @override
  Future<CatchFeedPage> timelineForSpecies(
    String speciesScientificName, {
    CatchTimelineCursor? cursor,
  }) async {
    if (CatchListEndpoints.useSpeciesId) {
      for (final e in _speciesIdToScientificName.entries) {
        if (e.value == speciesScientificName) {
          return _fetch(scientificName: null, speciesId: e.key, cursor: cursor);
        }
      }
    }
    return _fetch(scientificName: speciesScientificName, speciesId: null, cursor: cursor);
  }

  @override
  Future<List<CatchFeedItem>> userPhotosForSpecies(String speciesScientificName) async {
    final page = await timelineForSpecies(speciesScientificName);
    return page.items;
  }

  // ---- 本地缓存（SharedPreferences）：首页宫格全量数据 ----
  static const _homeLocalCacheKey = 'remote_home_cache_v1';

  static Map<String, dynamic> _itemToMap(CatchFeedItem item) => {
        'id': item.id,
        'sn': item.scientificName,
        'n': item.notes,
        'w': item.weightKg,
        'l': item.lengthCm,
        'loc': item.locationLabel,
        'lat': item.lat,
        'lng': item.lng,
        'at': item.occurredAt.millisecondsSinceEpoch,
        'url': item.imageUrl,
        'pub': item.fromPublished,
        'spid': item.sourcePublishedId,
        'rs': item.reviewStatus.wireValue,
      };

  static CatchFeedItem _itemFromMap(Map<String, dynamic> m) => CatchFeedItem(
        id: m['id'] as String? ?? '',
        scientificName: m['sn'] as String? ?? '',
        notes: m['n'] as String? ?? '',
        weightKg: (m['w'] as num?)?.toDouble() ?? 0,
        lengthCm: (m['l'] as num?)?.toDouble() ?? 0,
        locationLabel: m['loc'] as String? ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          m['at'] as int? ?? 0,
          isUtc: true,
        ),
        imageUrl: m['url'] as String? ?? '',
        fromPublished: m['pub'] as bool? ?? true,
        sourcePublishedId: m['spid'] as String?,
        reviewStatus: parseCatchReviewStatusLocal(m['rs']),
      );

  Future<void> _saveHomeCache(List<CatchFeedItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _homeLocalCacheKey,
        jsonEncode(items.map(_itemToMap).toList()),
      );
    } catch (e) {
      debugPrint('RemoteCatchRepository: home cache save failed: $e');
    }
  }

  Future<List<CatchFeedItem>> _loadHomeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_homeLocalCacheKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => _itemFromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('RemoteCatchRepository: home cache load failed: $e');
      return [];
    }
  }

  @override
  Future<List<CatchFeedItem>> allHomeItems() async {
    if (!_auth.isReady || !_auth.isLoggedIn) {
      return _loadHomeCache();
    }
    final all = <CatchFeedItem>[];
    CatchTimelineCursor? cursor;
    while (true) {
      final page = await _fetch(scientificName: null, speciesId: null, cursor: cursor);
      all.addAll(page.items);
      if (!page.hasMore || page.nextCursor == null) break;
      cursor = page.nextCursor;
    }
    unawaited(_saveHomeCache(all));
    return all;
  }

  @override
  Future<PublishedCatch?> getById(String id) async {
    if (!_auth.isReady || !_auth.isLoggedIn) return null;
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    try {
      final res = await _api.get<dynamic>(CatchPublishEndpoints.updatePath(trimmed));
      final json = res.data;
      if (json is! Map<String, dynamic>) return null;
      final dto = CatchRecordDto.fromJson(json);
      return publishedCatchFromDto(dto);
    } catch (e, st) {
      debugPrint('RemoteCatchRepository.getById failed: $e\n$st');
      return null;
    }
  }

  @override
  Future<void> upsertLocal(PublishedCatch publishedCatch) async {}

  Uint8List? _rawImageBytes(PublishedCatch publishedCatch, Uint8List? preferred) {
    if (preferred != null && preferred.isNotEmpty) return preferred;
    final b64 = publishedCatch.imageBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        return Uint8List.fromList(base64Decode(b64));
      } catch (e, st) {
        debugPrint('RemoteCatchRepository base64 decode failed: $e\n$st');
      }
    }
    return null;
  }

  @override
  Future<void> publish(
    PublishedCatch publishedCatch, {
    Uint8List? imageBytes,
    bool updating = false,
    String? updateId,
    String? speciesZh,
    String? taxonomyZh,
    bool? imageAuthorized,
  }) async {
    if (!_auth.isReady || !_auth.isLoggedIn) {
      throw ApiException(message: '请先登录后再发布');
    }

    final raw = _rawImageBytes(publishedCatch, imageBytes);
    Uint8List? jpeg;
    if (raw != null && raw.isNotEmpty) {
      jpeg = CatchPublishImagePrepare.toUploadJpeg(raw);
    }

    final usePut = updating &&
        updateId != null &&
        updateId.isNotEmpty &&
        _uuidPattern.hasMatch(updateId);

    if (!usePut && (jpeg == null || jpeg.isEmpty)) {
      throw ApiException(message: '请添加照片后再发布');
    }

    final form = buildCatchPublishFormData(
      publishedCatch,
      imageJpegBytes: jpeg,
      speciesZh: speciesZh,
      taxonomyZh: taxonomyZh,
      imageAuthorized: imageAuthorized,
    );

    if (usePut) {
      await _api.putMultipart(
        CatchPublishEndpoints.updatePath(updateId),
        data: form,
      );
    } else {
      await _api.postMultipart(
        CatchPublishEndpoints.createPath,
        data: form,
      );
    }

    _bumpAfterMutation();
  }

  @override
  Future<void> deletePublished(String id) async {
    if (!_auth.isReady || !_auth.isLoggedIn) {
      throw ApiException(message: '请先登录后再操作');
    }
    final trimmed = id.trim();
    if (trimmed.isEmpty || !_uuidPattern.hasMatch(trimmed)) {
      throw ApiException(message: '无法删除该记录');
    }
    await _api.delete<dynamic>(CatchPublishEndpoints.updatePath(trimmed));
    _bumpAfterMutation();
  }
}

class _CacheEntry<T> {
  _CacheEntry(this.value) : _created = DateTime.now();
  final T value;
  final DateTime _created;
  bool get isExpired =>
      DateTime.now().difference(_created) > RemoteCatchRepository._cacheTtl;
}
