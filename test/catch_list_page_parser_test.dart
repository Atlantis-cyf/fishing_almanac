import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_almanac/api/dto/catch_list_page_parser.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';

void main() {
  group('CatchListPageParser', () {
    test('parses items + next_cursor + has_more', () {
      final page = CatchListPageParser.parse(
        {
          'items': [
            {
              'id': 'a1',
              'scientific_name': 'Thunnus thynnus',
              'notes': 'n',
              'weight_kg': 1,
              'length_cm': 2,
              'location_label': 'L',
              'occurred_at': '2024-01-01T00:00:00Z',
            },
          ],
          'has_more': true,
          'next_cursor': {'occurred_at_ms': 1700000000000, 'id': 'a1'},
        },
        limit: 20,
      );
      expect(page.items.length, 1);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor?.occurredAtMs, 1700000000000);
      expect(page.nextCursor?.id, 'a1');
    });

    test('parses review_status on list item', () {
      final page = CatchListPageParser.parse(
        {
          'items': [
            {
              'id': 'b1',
              'scientific_name': 'x',
              'notes': '',
              'weight_kg': 0,
              'length_cm': 0,
              'location_label': '',
              'occurred_at': '2024-01-01T00:00:00Z',
              'review_status': 'pending_review',
            },
          ],
          'has_more': false,
        },
        limit: 20,
      );
      expect(page.items.single.reviewStatus, CatchReviewStatus.pendingReview);
    });

    test('unwraps data wrapper', () {
      final page = CatchListPageParser.parse(
        {
          'data': {
            'items': <dynamic>[],
            'has_more': false,
          },
        },
        limit: 20,
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('empty list without has_more is not hasMore', () {
      final page = CatchListPageParser.parse(
        {'items': <dynamic>[]},
        limit: 20,
      );
      expect(page.hasMore, isFalse);
    });
  });
}
