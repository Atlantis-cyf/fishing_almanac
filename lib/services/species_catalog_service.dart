import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/species_catalog_entry.dart';

/// Fetches the species catalog from the server and merges with the local
/// static catalog. Notifies listeners when the merged list changes.
class SpeciesCatalogService extends ChangeNotifier {
  SpeciesCatalogService({required ApiClient api}) : _api = api;

  final ApiClient _api;

  List<SpeciesCatalogEntry>? _serverEntries;
  List<SpeciesCatalogEntry>? _merged;
  DateTime? _lastFetch;
  bool _fetching = false;

  /// 已规范化学名键（含异名），用于首页等 O(1) 稀有统计；随合并图鉴失效。
  Set<String>? _rareScientificKeySet;

  static const Duration _cacheTtl = Duration(minutes: 5);

  /// The merged catalog: server entries override local ones by scientific_name.
  List<SpeciesCatalogEntry> get all {
    if (_merged != null) return _withSystemEntries(_merged!);
    return _withSystemEntries(SpeciesCatalog.all);
  }

  bool get hasFetched => _serverEntries != null;

  SpeciesCatalogEntry? tryByScientificName(String raw) {
    final k = SpeciesCatalog.normalizeScientificNameKey(raw);
    if (k.isEmpty) return null;
    for (final e in all) {
      if (SpeciesCatalog.normalizeScientificNameKey(e.scientificName) == k) {
        return e;
      }
    }
    // Also check synonyms
    for (final e in all) {
      for (final syn in e.allSynonyms) {
        if (SpeciesCatalog.normalizeScientificNameKey(syn) == k) return e;
      }
    }
    return null;
  }

  /// Resolve a Chinese name (or alias) to a catalog entry.
  SpeciesCatalogEntry? tryByZhOrAlias(String zhName) {
    final q = zhName.trim();
    if (q.isEmpty) return null;
    // Exact Chinese name match
    for (final e in all) {
      if (e.speciesZh == q) return e;
    }
    // Alias match
    for (final e in all) {
      if (e.allAliasZh.contains(q)) return e;
    }
    return null;
  }

  void _invalidateRareKeyCache() {
    _rareScientificKeySet = null;
  }

  Set<String> get _rareScientificNameKeys {
    _rareScientificKeySet ??= _computeRareScientificKeys(all);
    return _rareScientificKeySet!;
  }

  static Set<String> _computeRareScientificKeys(List<SpeciesCatalogEntry> entries) {
    final keys = <String>{};
    for (final e in entries) {
      if (!e.countsAsRareSpecies) continue;
      keys.add(SpeciesCatalog.normalizeScientificNameKey(e.scientificName));
      for (final syn in e.allSynonyms) {
        keys.add(SpeciesCatalog.normalizeScientificNameKey(syn));
      }
    }
    return keys;
  }

  /// 用户时间线中去重后的学名列表里，命中珍惜/稀有图鉴（含异名）的种数。
  int countUnlockedRareSpecies(Iterable<String> scientificNamesRaw) {
    final rare = _rareScientificNameKeys;
    var n = 0;
    for (final s in scientificNamesRaw) {
      if (rare.contains(SpeciesCatalog.normalizeScientificNameKey(s))) n++;
    }
    return n;
  }

  /// Fetch the species catalog from the server, merge with local, and notify.
  /// Safe to call multiple times; skips if cache is fresh or a fetch is in flight.
  Future<void> fetchIfNeeded() async {
    if (_fetching) return;
    if (_lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheTtl) {
      return;
    }
    _fetching = true;
    try {
      final res = await _api.get<dynamic>(SpeciesCatalogEndpoints.list);
      final data = res.data as Map<String, dynamic>? ?? {};
      final speciesList = data['species'];
      if (speciesList is List) {
        _serverEntries = speciesList
            .whereType<Map<String, dynamic>>()
            .map((m) => SpeciesCatalogEntry.fromServerJson(m))
            .toList();
        _rebuildMerged();
        _lastFetch = DateTime.now();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[SpeciesCatalogService] fetch failed: $e');
    } finally {
      _fetching = false;
    }
  }

  /// Remote search: query the backend `/v1/species/search` endpoint which
  /// matches species_zh, alias_zh, scientific_name, synonyms, and aliases.
  Future<List<SpeciesCatalogEntry>> remoteSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final res = await _api.get<dynamic>(
        SpeciesCatalogEndpoints.search,
        queryParameters: {'q': q},
      );
      final data = res.data as Map<String, dynamic>? ?? {};
      final results = data['results'];
      if (results is List) {
        return results
            .whereType<Map<String, dynamic>>()
            .map((m) => SpeciesCatalogEntry.fromServerJson(m))
            .toList();
      }
    } catch (e) {
      debugPrint('[SpeciesCatalogService] remoteSearch failed: $e');
    }
    return const [];
  }

  /// Force a refetch on next call.
  void invalidate() {
    _lastFetch = null;
    _invalidateRareKeyCache();
  }

  void _rebuildMerged() {
    _invalidateRareKeyCache();
    final server = _serverEntries;
    if (server == null || server.isEmpty) {
      _merged = null;
      return;
    }

    final byScientific = <String, SpeciesCatalogEntry>{};

    // Local entries first (base)
    for (final e in SpeciesCatalog.all) {
      byScientific[SpeciesCatalog.normalizeScientificNameKey(e.scientificName)] = e;
    }

    // Server entries override or add
    for (final e in server) {
      byScientific[SpeciesCatalog.normalizeScientificNameKey(e.scientificName)] = e;
    }

    _merged = byScientific.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  List<SpeciesCatalogEntry> _withSystemEntries(List<SpeciesCatalogEntry> source) {
    final hasOther = source.any(
      (e) =>
          SpeciesCatalog.normalizeScientificNameKey(e.scientificName) ==
          SpeciesCatalog.normalizeScientificNameKey(SpeciesCatalog.otherScientificName),
    );
    if (hasOther) return source;
    return <SpeciesCatalogEntry>[...source, SpeciesCatalog.otherEntry];
  }
}
