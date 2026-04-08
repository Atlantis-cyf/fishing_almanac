import 'package:flutter/material.dart';

import 'package:fishing_almanac/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 字体使用 pubspec 中 assets/fonts 的 Manrope / Inter，不依赖 Google CDN。
  runApp(const FishingAlmanacApp());
}
