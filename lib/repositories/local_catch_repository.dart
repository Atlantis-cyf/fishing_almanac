import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

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

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(_items.map((e) => e.toJson()).toList()));
      _clearError();
    } catch (e, st) {
      debugPrint('LocalCatchRepository._persist failed: $e\n$st');
      throw PersistenceException('无法保存鱼获到本地，请重试', cause: e);
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
    final i = _items.indexWhere((e) => e.id == publishedCatch.id);
    if (i >= 0) {
      _items[i] = publishedCatch;
    } else {
      _items.add(publishedCatch);
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
  }) async {
    await upsertLocal(publishedCatch);
  }
}
