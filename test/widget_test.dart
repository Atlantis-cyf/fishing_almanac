import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_almanac/app.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FishingAlmanacApp());
    await tester.pump();
    expect(find.text('海钓图鉴'), findsOneWidget);
  });
}
