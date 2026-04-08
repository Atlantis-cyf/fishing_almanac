import 'dart:typed_data';

/// 鱼种识别结果。接入真实模型后由 [SpeciesIdentificationService.identifySpecies] 填充。
class SpeciesIdentificationResult {
  const SpeciesIdentificationResult({
    required this.scientificName,
    required this.confidence,
    this.isFish = true,
    this.speciesZh,
    this.taxonomyZh,
    this.inCatalog = true,
    this.rawLabel,
    this.metadata,
  });

  /// AI 判断图片中是否有鱼。
  final bool isFish;

  /// 与 `species_catalog.scientific_name` 对齐的稳定标识。
  final String scientificName;

  /// AI 返回的中文名。
  final String? speciesZh;

  /// AI 返回的分类文案（纲·目·科）。
  final String? taxonomyZh;

  /// 匹配置信度，范围建议 **0.0 ~ 1.0**。
  final double confidence;

  /// 该物种是否已存在于服务端 species_catalog。
  final bool inCatalog;

  /// 模型原始类别标签（可选）。
  final String? rawLabel;

  /// 扩展字段：bbox、多标签、耗时等，便于后期接入。
  final Map<String, dynamic>? metadata;

  int get confidencePercent => (confidence.clamp(0, 1) * 100).round();
}

/// 鱼种识别服务抽象。后期可替换为：
/// - 设备端 TFLite / ONNX
/// - 自定义 isolate 推理
/// - 云端 HTTP / gRPC
///
/// 在 [EditCatchScreen] 或其它流程中通过 `Provider` / 依赖注入切换实现即可。
abstract class SpeciesIdentificationService {
  const SpeciesIdentificationService();

  /// 根据照片识别鱼种。实现类可只使用 [imageBytes] 或只使用 [imageUrl]，或二者融合。
  Future<SpeciesIdentificationResult> identifySpecies({
    Uint8List? imageBytes,
    String? imageUrl,
  });
}

/// 占位实现：固定返回示例结果，不调用真实模型。
class StubSpeciesIdentificationService implements SpeciesIdentificationService {
  const StubSpeciesIdentificationService();

  @override
  Future<SpeciesIdentificationResult> identifySpecies({
    Uint8List? imageBytes,
    String? imageUrl,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final hasBytes = imageBytes != null && imageBytes.isNotEmpty;
    final hasUrl = imageUrl != null && imageUrl.isNotEmpty;
    if (!hasBytes && !hasUrl) {
      return const SpeciesIdentificationResult(scientificName: '—', confidence: 0);
    }
    // 占位：勿使用易与真实鱼种混淆的学名；需要真实识别请启用 Remote（默认已开）。
    return const SpeciesIdentificationResult(
      scientificName: 'Indeterminate',
      confidence: 0,
      speciesZh: '未确定',
      rawLabel: 'stub_no_model',
      metadata: {'engine': 'stub', 'version': 0},
    );
  }
}
