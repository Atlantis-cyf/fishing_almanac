import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:fishing_almanac/api/catch_publish_image_prepare.dart';
import 'package:fishing_almanac/data/catch_feed_data.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/published_catch.dart';
import 'package:fishing_almanac/repositories/catch_feed_page.dart';
import 'package:fishing_almanac/repositories/catch_repository.dart';
import 'package:fishing_almanac/repositories/catch_timeline_cursor.dart';
import 'package:fishing_almanac/repositories/persistence_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地持久化实现（`published_catches_v1`），JSON 仅在此类内解析。
class LocalCatchRepository extends CatchRepository {
  LocalCatchRepository() {
    _loadFuture = _loadFromDisk();
  }

  static const _key = 'published_catches_v1';

  /// Base64 超过此长度则压 JPEG 后再存，降低 SharedPreferences 单 key 体积（Web 易失败）。
  static const _base64CompactThreshold = 120000;

  final List<PublishedCatch> _items = [];
  late final Future<void> _loadFuture;
  int _dataGeneration = 0;

  /// 最近一次加载失败说明（成功持久化会清空）。
  String? _lastError;

  void _clearError() => _lastError = null;

  @override
  String? get persistenceHint => _lastError;

  @override
  String? consumePersistenceHint() {
    final h = _lastError;
    if (h == null) return null;
    _lastError = null;
    notifyListeners();
    return h;
  }

  @override
  int get dataGeneration => _dataGeneration;

  void _bump() {
    _dataGeneration++;
    notifyListeners();
  }

  Future<void> _ensureLoaded() => _loadFuture;

  Future<void> _loadFromDisk() async {
    _clearError();
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) {
        _bump();
        return;
      }
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _items
          ..clear()
          ..addAll(list.map((e) => PublishedCatch.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (e, st) {
        _items.clear();
        _lastError = '本地鱼获数据损坏或版本不兼容，已重置列表';
        debugPrint('LocalCatchRepository._loadFromDisk parse failed: $e\n$st');
        notifyListeners();
      }
    } catch (e, st) {
      _lastError = '无法读取本地鱼获缓存：$e';
      debugPrint('LocalCatchRepository._loadFromDisk failed: $e\n$st');
      notifyListeners();
    }
    _bump();
  }

  PublishedCatch _compactForLocalStorage(PublishedCatch p) {
    final b64 = p.imageBase64;
    if (b64 == null || b64.isEmpty) return p;
    if (b64.length < _base64CompactThreshold) return p;
    try {
      final raw = base64Decode(b64);
      final jpeg = CatchPublishImagePrepare.toLocalPersistJpeg(raw);
      if (jpeg.isEmpty || jpeg.length >= raw.length) return p;
      final outB64 = base64Encode(jpeg);
      if (outB64.length >= b64.length) return p;
      return PublishedCatch(
        id: p.id,
        imageBase64: outB64,
        imageUrlFallback: p.imageUrlFallback,
        scientificName: p.scientificName,
        notes: p.notes,
        weightKg: p.weightKg,
        lengthCm: p.lengthCm,
        locationLabel: p.locationLabel,
        lat: p.lat,
        lng: p.lng,
        occurredAt: p.occurredAt,
        reviewStatus: p.reviewStatus,
      );
    } catch (e, st) {
      debugPrint('LocalCatchRepository._compactForLocalStorage skipped: $e\n$st');
      return p;
    }
  }

  void _compactAllItemsInMemory() {
    for (var i = 0; i < _items.length; i++) {
      _items[i] = _compactForLocalStorage(_items[i]);
    }
  }

  Future<void> _persist() async {
    try {
      _compactAllItemsInMemory();
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(_items.map((e) => e.toJson()).toList()));
      _clearError();
    } catch (e, st) {
      debugPrint('LocalCatchRepository._persist failed: $e\n$st');
      const webHint =
          '无法保存鱼获到本地（网页存储有大小限制）。请压缩照片、减少条数，或使用 flutter run --dart-define=USE_REMOTE_CATCH_REPOSITORY=true 同步到服务器。';
      const nativeHint = '无法保存鱼获到本地，请重试';
      throw PersistenceException(kIsWeb ? webHint : nativeHint, cause: e);
    }
  }

  @override
  Future<CatchFeedPage> timelineHome({CatchTimelineCursor? cursor}) async {
    await _ensureLoaded();
    final items = CatchFeedData.timelineHomeFromPublished(_items);
    return CatchFeedPage(items: items, hasMore: false);
  }

  @override
  Future<CatchFeedPage> timelineForSpecies(
    String speciesScientificName, {
    CatchTimelineCursor? cursor,
  }) async {
    await _ensureLoaded();
    final items = CatchFeedData.timelineForSpeciesFromPublished(_items, speciesScientificName);
    return CatchFeedPage(items: items, hasMore: false);
  }

  @override
  Future<List<CatchFeedItem>> userPhotosForSpecies(String speciesScientificName) async {
    await _ensureLoaded();
    return CatchFeedData.userPhotosForSpeciesFromPublished(_items, speciesScientificName);
  }

  @override
  Future<PublishedCatch?> getById(String id) async {
    await _ensureLoaded();
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Future<void> upsertLocal(PublishedCatch publishedCatch) async {
    await _ensureLoaded();
    final toStore = _compactForLocalStorage(publishedCatch);
    final i = _items.indexWhere((e) => e.id == toStore.id);
    if (i >= 0) {
      _items[i] = toStore;
    } else {
      _items.add(toStore);
    }
    await _persist();
    _bump();
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
    await upsertLocal(publishedCatch);
  }

  @override
  Future<void> deletePublished(String id) async {
    await _ensureLoaded();
    final before = _items.length;
    _items.removeWhere((e) => e.id == id);
    if (_items.length == before) return;
    await _persist();
    _bump();
  }
}
