import 'package:flutter/material.dart';

/// 与 HTML Tailwind 扩展色板对齐的语义色。
abstract final class AppColors {
  static const Color background = Color(0xFF0b1326);
  static const Color surface = Color(0xFF0b1326);
  static const Color surfaceDim = Color(0xFF0b1326);
  static const Color surfaceContainer = Color(0xFF171f33);
  static const Color surfaceContainerLow = Color(0xFF131b2e);
  static const Color surfaceContainerLowest = Color(0xFF060e20);
  static const Color surfaceContainerHigh = Color(0xFF222a3d);
  static const Color surfaceContainerHighest = Color(0xFF2d3449);
  static const Color surfaceVariant = Color(0xFF2d3449);
  static const Color surfaceBright = Color(0xFF31394d);

  static const Color primary = Color(0xFFc3f5ff);
  static const Color onPrimary = Color(0xFF00363d);
  static const Color primaryContainer = Color(0xFF00e5ff);
  static const Color onPrimaryContainer = Color(0xFF00626e);

  static const Color secondary = Color(0xFFd7ffc5);
  static const Color onSecondary = Color(0xFF053900);
  static const Color secondaryContainer = Color(0xFF2ff801);
  static const Color onSecondaryContainer = Color(0xFF0f6d00);
  static const Color secondaryFixed = Color(0xFF79ff5b);

  static const Color tertiary = Color(0xFFd6f1ff);
  static const Color onTertiary = Color(0xFF003545);

  static const Color onBackground = Color(0xFFdae2fd);
  static const Color onSurface = Color(0xFFdae2fd);
  static const Color onSurfaceVariant = Color(0xFFbac9cc);
  static const Color outline = Color(0xFF849396);
  static const Color outlineVariant = Color(0xFF3b494c);

  static const Color error = Color(0xFFffb4ab);
  static const Color errorContainer = Color(0xFF93000a);
  static const Color onError = Color(0xFF690005);

  static const Color cyanNav = Color(0xFF22d3ee); // cyan-400
  static const Color slateNavInactive = Color(0xFF94a3b8); // slate-400
  static const Color slate900 = Color(0xFF0f172a);
}
