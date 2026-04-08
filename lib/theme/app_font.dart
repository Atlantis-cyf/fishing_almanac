import 'package:flutter/material.dart';

/// 使用 [pubspec.yaml] 中打包的 Manrope 可变字体（family: Manrope）。
/// 不依赖 google_fonts 运行时下载，适合国内网络环境。
///
/// Manrope / Inter 对 CJK 覆盖不全（如「鲯」），缺字时由 [cjkFallback] 回退到系统中文黑体。
abstract final class AppFont {
  /// Web/桌面/移动端常见中文字体名；按顺序选用本机已安装的第一种。
  static const List<String> cjkFallback = [
    'Microsoft YaHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'SimSun',
    'sans-serif',
  ];

  static TextStyle manrope({
    bool? inherit,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    TextLeadingDistribution? leadingDistribution,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    List<FontVariation>? fontVariations,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
    TextOverflow? overflow,
  }) {
    return TextStyle(
      inherit: inherit ?? true,
      fontFamily: 'Manrope',
      fontFamilyFallback: cjkFallback,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textBaseline: textBaseline,
      height: height,
      leadingDistribution: leadingDistribution,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      fontVariations: fontVariations,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
      overflow: overflow,
    );
  }
}
