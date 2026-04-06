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

  static const Duration _cacheTtl = Duration(minutes: 5);

  /// The merged catalog: server entries override local ones by scientific_name.
  List<SpeciesCatalogEntry> get all {
    if (_merged != null) return _merged!;
    return SpeciesCatalog.all;
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
    return null;
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

  /// Force a refetch on next call.
  void invalidate() {
    _lastFetch = null;
  }

  void _rebuildMerged() {
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
}
