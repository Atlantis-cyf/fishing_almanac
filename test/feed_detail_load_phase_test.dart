import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_almanac/screens/feed_detail_screen.dart';

void main() {
  test('FeedDetailLoadPhase has loading, empty, error, success', () {
    expect(FeedDetailLoadPhase.values, contains(FeedDetailLoadPhase.loading));
    expect(FeedDetailLoadPhase.values, contains(FeedDetailLoadPhase.empty));
    expect(FeedDetailLoadPhase.values, contains(FeedDetailLoadPhase.error));
    expect(FeedDetailLoadPhase.values, contains(FeedDetailLoadPhase.success));
    expect(FeedDetailLoadPhase.values.length, 4);
  });
}
