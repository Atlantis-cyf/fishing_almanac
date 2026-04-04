import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/api/catch_publish_image_prepare.dart';
import 'package:fishing_almanac/api/catch_publish_multipart.dart';
import 'package:fishing_almanac/api/dto/catch_list_page_parser.dart';
import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/published_catch.dart';
import 'package:fishing_almanac/repositories/catch_feed_page.dart';
import 'package:fishing_almanac/repositories/catch_repository.dart';
import 'package:fishing_almanac/repositories/catch_timeline_cursor.dart';

/// 远程列表 + multipart 发布。
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

  /// 与 BFF 占位 `species_id` 映射一致（拉丁学名）。
  static const Map<int, String> _speciesIdToScientificName = {
    1: 'Thunnus thynnus',
    2: 'Coryphaena hippurus',
    3: 'Lutjanus campechanus',
    4: 'Anyperodon leucogrammicus',
    5: 'Morone saxatilis',
  };

  int _mutationGen = 0;

  @override
  int get dataGeneration => _mutationGen;

  @override
  bool get usesRemoteTimeline => true;

  void _bumpAfterMutation() {
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

  @override
  Future<PublishedCatch?> getById(String id) async => null;

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

    final form = buildCatchPublishFormData(publishedCatch, imageJpegBytes: jpeg);

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
