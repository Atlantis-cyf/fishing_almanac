import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_almanac/models/feed_detail_extra.dart';
import 'package:fishing_almanac/router/feed_detail_route_args.dart';

void main() {
  group('parseFeedDetailRouteArgsRaw', () {
    test('query species (zh) resolves to scientific name', () {
      final u = Uri(
        scheme: 'https',
        host: 'x',
        path: '/feed-detail',
        queryParameters: {'species': '鲯鳅', 'index': '2'},
      );
      final a = parseFeedDetailRouteArgsRaw(uri: u);
      expect(a.speciesScientificName, 'Coryphaena hippurus');
      expect(a.initialIndex, 2);
    });

    test('path scientificName segment (zh) resolves', () {
      final u = Uri(
        scheme: 'https',
        host: 'x',
        path: '/feed-detail/石斑鱼',
        queryParameters: {'i': '1'},
      );
      final a = parseFeedDetailRouteArgsRaw(
        uri: u,
        pathParameters: {'scientificName': '石斑鱼'},
      );
      expect(a.speciesScientificName, 'Anyperodon leucogrammicus');
      expect(a.initialIndex, 1);
    });

    test('FeedDetailExtra overrides index, species from query when extra species null', () {
      final u = Uri(path: '/feed-detail', queryParameters: {'species': '红鲷鱼'});
      final a = parseFeedDetailRouteArgsRaw(
        uri: u,
        extra: const FeedDetailExtra(initialIndex: 5, speciesScientificName: null),
      );
      expect(a.initialIndex, 5);
      expect(a.speciesScientificName, '红鲷鱼');
    });

    test('FeedDetailExtra species wins over query', () {
      final u = Uri(path: '/feed-detail', queryParameters: {'species': '红鲷'});
      final a = parseFeedDetailRouteArgsRaw(
        uri: u,
        extra: const FeedDetailExtra(initialIndex: 0, speciesScientificName: '鲯鳅'),
      );
      expect(a.speciesScientificName, 'Coryphaena hippurus');
    });

    test('query scientific_name kept when already latin', () {
      final u = Uri(
        path: '/feed-detail',
        queryParameters: {'scientific_name': 'Thunnus thynnus'},
      );
      final a = parseFeedDetailRouteArgsRaw(uri: u);
      expect(a.speciesScientificName, 'Thunnus thynnus');
    });

    test('query catch_id and FeedDetailExtra anchorCatchId', () {
      final u = Uri(
        path: '/feed-detail',
        queryParameters: {'catch_id': 'pub-1'},
      );
      final a = parseFeedDetailRouteArgsRaw(uri: u);
      expect(a.anchorCatchId, 'pub-1');
      final b = parseFeedDetailRouteArgsRaw(
        uri: u,
        extra: const FeedDetailExtra(anchorCatchId: 'extra-id'),
      );
      expect(b.anchorCatchId, 'extra-id');
    });
  });

  group('sanitizePostLoginRedirectQuery', () {
    test('accepts path with query', () {
      expect(
        sanitizePostLoginRedirectQuery('/feed-detail?scientific_name=Thunnus%20thynnus'),
        '/feed-detail?scientific_name=Thunnus%20thynnus',
      );
    });

    test('rejects external-like', () {
      expect(sanitizePostLoginRedirectQuery('//evil.com'), isNull);
      expect(sanitizePostLoginRedirectQuery('/a/../b'), isNull);
    });
  });
}
