import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';

class PublishedCatch {
  PublishedCatch({
    required this.id,
    this.imageBase64,
    this.imageUrlFallback,
    required this.scientificName,
    required this.notes,
    required this.weightKg,
    required this.lengthCm,
    required this.locationLabel,
    this.lat,
    this.lng,
    required this.occurredAt,
    this.reviewStatus = CatchReviewStatus.approved,
  });

  final String id;
  final String? imageBase64;
  final String? imageUrlFallback;
  /// 与 `species_catalog.scientific_name` 一致。
  final String scientificName;
  final String notes;
  final double weightKg;
  final double lengthCm;
  final String locationLabel;
  final double? lat;
  final double? lng;
  final DateTime occurredAt;
  final CatchReviewStatus reviewStatus;

  Map<String, dynamic> toJson() => {
        'id': id,
        'imageBase64': imageBase64,
        'imageUrlFallback': imageUrlFallback,
        'scientificName': scientificName,
        'notes': notes,
        'weightKg': weightKg,
        'lengthCm': lengthCm,
        'locationLabel': locationLabel,
        'lat': lat,
        'lng': lng,
        'occurredAt': occurredAt.toIso8601String(),
        'reviewStatus': reviewStatus.wireValue,
      };

  factory PublishedCatch.fromJson(Map<String, dynamic> j) => PublishedCatch(
        id: _jsonIdToString(j['id']),
        imageBase64: j['imageBase64'] as String?,
        imageUrlFallback: j['imageUrlFallback'] as String?,
        scientificName: _scientificNameFromJson(j),
        notes: j['notes'] as String? ?? '',
        weightKg: (j['weightKg'] as num?)?.toDouble() ?? 0,
        lengthCm: (j['lengthCm'] as num?)?.toDouble() ?? 0,
        locationLabel: j['locationLabel'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        occurredAt: _parseOccurredAt(j),
        reviewStatus: parseCatchReviewStatusLocal(j['reviewStatus'] ?? j['review_status']),
      );

  static String _scientificNameFromJson(Map<String, dynamic> j) {
    final sn = (j['scientificName'] ?? j['scientific_name'])?.toString().trim() ?? '';
    if (sn.isNotEmpty) return sn;
    final legacyZh = (j['speciesZh'] ?? j['species_zh'])?.toString().trim() ?? '';
    if (legacyZh.isEmpty) return '';
    final hit = SpeciesCatalog.tryBySpeciesZh(legacyZh);
    return hit?.scientificName ?? legacyZh;
  }

  static String _jsonIdToString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  /// 业务时间：数值毫秒字段优先（`*_ms` / `*Ms`）；否则 ISO8601（`occurredAt` / `occurred_at`）。
  static DateTime _parseOccurredAt(Map<String, dynamic> j) {
    for (final key in ['occurred_at_ms', 'occurredAtMs']) {
      final v = j[key];
      if (v is num) {
        return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
      }
    }
    final s = (j['occurredAt'] ?? j['occurred_at'])?.toString().trim() ?? '';
    if (s.isNotEmpty) {
      final d = DateTime.tryParse(s);
      if (d != null) return d;
    }
    debugPrint('PublishedCatch: missing occurred_at for id=${_jsonIdToString(j['id'])}, defaulting to epoch');
    return DateTime.utc(1970);
  }

  CatchFeedItem toFeedItem() {
    Uint8List? bytes;
    if (imageBase64 != null && imageBase64!.isNotEmpty) {
      try {
        bytes = base64Decode(imageBase64!);
      } catch (_) {}
    }
    return CatchFeedItem(
      id: id,
      sourcePublishedId: id,
      imageBytes: bytes,
      imageUrl: imageUrlFallback ?? '',
      scientificName: scientificName,
      notes: notes,
      weightKg: weightKg,
      lengthCm: lengthCm,
      locationLabel: locationLabel,
      lat: lat,
      lng: lng,
      occurredAt: occurredAt,
      fromPublished: true,
      reviewStatus: reviewStatus,
    );
  }
}
