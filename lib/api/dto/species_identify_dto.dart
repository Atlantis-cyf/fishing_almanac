import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/data/species_catalog.dart';

/// 识别接口 JSON → 应用层结果（支持根级或 `data` 包裹）。
/// 优先 [scientificName]；仅有中文等字段时尝试图鉴映射为学名。
class SpeciesIdentifyPayload {
  const SpeciesIdentifyPayload._({
    required this.scientificName,
    required this.confidence,
    this.isFish = true,
    this.speciesZh,
    this.taxonomyZh,
    this.inCatalog = true,
    this.rawLabel,
    this.metadata,
  });

  final bool isFish;
  final String scientificName;
  final String? speciesZh;
  final String? taxonomyZh;
  final double confidence;
  final bool inCatalog;
  final String? rawLabel;
  final Map<String, dynamic>? metadata;

  /// 解析成功响应体；格式不合法时抛出 [ApiException]（由上层转为 SnackBar 等）。
  factory SpeciesIdentifyPayload.fromResponseData(dynamic data) {
    final m = _unwrapMap(data);
    if (m == null) {
      throw ApiException(message: '识别服务返回数据无效');
    }
    final sci = _firstString(m, const [
      'scientific_name',
      'scientificName',
      'species_scientific',
      'speciesScientific',
    ]);
    final zh = _firstString(m, const [
      'species_zh',
      'speciesZh',
      'label_zh',
      'labelZh',
      'species',
      'name_zh',
      'nameZh',
    ]);
    String resolved;
    if (sci != null && sci.isNotEmpty) {
      resolved = sci;
    } else if (zh != null && zh.isNotEmpty) {
      resolved = SpeciesCatalog.tryBySpeciesZh(zh)?.scientificName ?? zh;
    } else {
      throw ApiException(message: '识别服务未返回鱼种名称');
    }
    final conf = _parseConfidence(m);
    final raw = _firstString(m, const ['raw_label', 'rawLabel', 'label']);
    Map<String, dynamic>? meta;
    final metaVal = m['metadata'];
    if (metaVal is Map) {
      meta = Map<String, dynamic>.from(metaVal);
    }
    final isFish = m['is_fish'] != false;
    final taxonomyZh = _firstString(m, const ['taxonomy_zh', 'taxonomyZh']);
    final inCatalog = m['in_catalog'] != false;
    return SpeciesIdentifyPayload._(
      isFish: isFish,
      scientificName: resolved,
      speciesZh: zh,
      taxonomyZh: taxonomyZh,
      confidence: conf,
      inCatalog: inCatalog,
      rawLabel: raw,
      metadata: meta,
    );
  }

  static Map<String, dynamic>? _unwrapMap(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      final root = Map<String, dynamic>.from(data);
      final inner = root['data'];
      if (inner is Map) {
        return Map<String, dynamic>.from(inner);
      }
      return root;
    }
    return null;
  }

  static String? _firstString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static double _parseConfidence(Map<String, dynamic> m) {
    final v = m['confidence'] ?? m['score'] ?? m['prob'] ?? m['probability'];
    if (v == null) return 0.85;
    if (v is num) return _normalizeConfidence(v.toDouble());
    if (v is String) {
      final p = double.tryParse(v.trim());
      if (p != null) return _normalizeConfidence(p);
    }
    return 0.85;
  }

  static double _normalizeConfidence(double x) {
    if (x > 1.0 && x <= 100.0) {
      return (x / 100.0).clamp(0.0, 1.0);
    }
    return x.clamp(0.0, 1.0);
  }
}
