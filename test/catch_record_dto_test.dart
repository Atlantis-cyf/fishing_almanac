import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_almanac/api/dto/catch_publish_response.dart';
import 'package:fishing_almanac/api/dto/catch_record_dto.dart';
import 'package:fishing_almanac/api/mappers/catch_record_mapper.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';
import 'package:fishing_almanac/models/published_catch.dart';

void main() {
  group('CatchRecordDto.fromJson', () {
    test('parses minimal JSON string from wire (legacy species_zh)', () {
      const raw =
          '{"id":"x","species_zh":"s","notes":"","weight_kg":0,"length_cm":0,"location_label":"","occurred_at":"2024-01-01T00:00:00Z"}';
      final d = CatchRecordDto.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      expect(d.id, 'x');
      expect(d.scientificName, 's');
      expect(d.occurredAt.isUtc, isTrue);
    });

    test('snake_case sample with legacy zh maps to scientific name', () {
      final d = CatchRecordDto.fromJson({
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'image_base64': null,
        'image_url': 'https://cdn.example.com/a.jpg',
        'species_zh': '蓝鳍金枪鱼',
        'notes': 'test',
        'weight_kg': 12.5,
        'length_cm': 100,
        'location_label': '东海',
        'lat': 30.0,
        'lng': 122.0,
        'occurred_at': '2024-06-15T08:30:00.000Z',
      });
      expect(d.id, '550e8400-e29b-41d4-a716-446655440000');
      expect(d.imageUrl, 'https://cdn.example.com/a.jpg');
      expect(d.scientificName, 'Thunnus maccoyii');
      expect(d.weightKg, 12.5);
      expect(d.lengthCm, 100.0);
      expect(d.locationLabel, '东海');
      expect(d.lat, 30.0);
      expect(d.lng, 122.0);
      expect(d.occurredAt.isUtc, isTrue);
      expect(d.occurredAt.toUtc().hour, 8);
    });

    test('scientific_name wire field', () {
      final d = CatchRecordDto.fromJson({
        'id': '1',
        'scientific_name': 'Coryphaena hippurus',
        'notes': '',
        'weight_kg': 0,
        'length_cm': 0,
        'location_label': '',
        'occurred_at': '2020-01-01T00:00:00Z',
      });
      expect(d.scientificName, 'Coryphaena hippurus');
    });

    test('id int coerces to String', () {
      final d = CatchRecordDto.fromJson({
        'id': 42,
        'species_zh': 'x',
        'notes': '',
        'weight_kg': 0,
        'length_cm': 0,
        'location_label': '',
        'occurred_at': '2020-01-01T00:00:00Z',
      });
      expect(d.id, '42');
    });

    test('occurred_at_ms takes precedence over occurred_at', () {
      final d = CatchRecordDto.fromJson({
        'id': '1',
        'species_zh': '',
        'notes': '',
        'weight_kg': 0,
        'length_cm': 0,
        'location_label': '',
        'occurred_at': '2020-01-01T00:00:00Z',
        'occurred_at_ms': 1700000000000,
      });
      expect(d.occurredAt.toUtc().millisecondsSinceEpoch, 1700000000000);
    });

    test('review_status maps to enum', () {
      final d = CatchRecordDto.fromJson({
        'id': '1',
        'species_zh': '',
        'notes': '',
        'weight_kg': 0,
        'length_cm': 0,
        'location_label': '',
        'occurred_at': '2020-01-01T00:00:00Z',
        'review_status': 'pending_review',
      });
      expect(d.reviewStatus, CatchReviewStatus.pendingReview);
    });
  });

  group('CatchRecordDto.toJson', () {
    test('occurred_at is UTC ISO8601 with Z', () {
      final local = DateTime(2024, 3, 1, 12, 0, 0);
      final d = CatchRecordDto(
        id: 'a',
        scientificName: 's',
        notes: 'n',
        weightKg: 1,
        lengthCm: 2,
        locationLabel: 'L',
        occurredAt: local,
      );
      final json = d.toJson();
      expect(json['occurred_at'], isA<String>());
      final s = json['occurred_at'] as String;
      expect(s.endsWith('Z'), isTrue);
      final parsed = DateTime.parse(s);
      expect(parsed.isUtc, isTrue);
      expect(json['scientific_name'], 's');
    });

    test('writes review_status when set', () {
      final d = CatchRecordDto(
        id: 'a',
        scientificName: 's',
        notes: 'n',
        weightKg: 1,
        lengthCm: 2,
        locationLabel: 'L',
        occurredAt: DateTime.utc(2024, 1, 1),
        reviewStatus: CatchReviewStatus.rejected,
      );
      expect(d.toJson()['review_status'], 'rejected');
    });
  });

  group('mappers', () {
    test('PublishedCatch roundtrip via DTO', () {
      final original = PublishedCatch(
        id: 'uuid-1',
        imageBase64: null,
        imageUrlFallback: 'https://x/y.png',
        scientificName: 'Coryphaena hippurus',
        notes: 'ok',
        weightKg: 3,
        lengthCm: 40,
        locationLabel: '近海',
        lat: 1.5,
        lng: 2.5,
        occurredAt: DateTime.utc(2023, 5, 5, 10, 0, 0),
      );
      final dto = publishedCatchToDto(original);
      final again = publishedCatchFromDto(dto);
      expect(again.id, original.id);
      expect(again.imageUrlFallback, original.imageUrlFallback);
      expect(again.scientificName, original.scientificName);
      expect(again.occurredAt, original.occurredAt);
      expect(again.reviewStatus, CatchReviewStatus.approved);
    });

    test('publishedCatchFromDto defaults absent review to approved for list', () {
      final d = CatchRecordDto(
        id: '1',
        scientificName: 'x',
        notes: '',
        weightKg: 0,
        lengthCm: 0,
        locationLabel: '',
        occurredAt: DateTime.utc(2020, 1, 1),
      );
      expect(publishedCatchFromDto(d).reviewStatus, CatchReviewStatus.approved);
    });

    test('tryParsePublishedCatchResponse defaults absent review to pendingReview', () {
      final p = tryParsePublishedCatchResponse({
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'scientific_name': 's',
        'notes': '',
        'weight_kg': 0,
        'length_cm': 0,
        'location_label': '',
        'occurred_at': '2024-01-01T00:00:00Z',
      });
      expect(p, isNotNull);
      expect(p!.reviewStatus, CatchReviewStatus.pendingReview);
    });

    test('CatchFeedItem toDto/fromDto preserves url and fromPublished flag', () {
      final item = CatchFeedItem(
        id: 'demo_0',
        scientificName: 'Thunnus thynnus',
        notes: 'n',
        weightKg: 1,
        lengthCm: 2,
        locationLabel: 'L',
        occurredAt: DateTime.utc(2020, 1, 2),
        imageUrl: 'https://cdn.example.com/p.jpg',
        fromPublished: false,
      );
      final dto = catchFeedItemToDto(item);
      expect(dto.imageUrl, 'https://cdn.example.com/p.jpg');
      expect(dto.imageBase64, isNull);
      final back = catchFeedItemFromDto(dto, fromPublished: false);
      expect(back.id, item.id);
      expect(back.fromPublished, isFalse);
      expect(back.imageUrl, item.imageUrl);
      expect(back.scientificName, item.scientificName);
    });
  });
}
