import 'package:fishing_almanac/data/species_catalog.dart';

class SpeciesItem {
  const SpeciesItem({
    required this.id,
    required this.name,
    required this.countLabel,
    required this.imageUrl,
    this.rarity,
    required this.speciesScientificName,
    required this.category,
  });

  final int id;
  final String name;
  final String countLabel;
  final String imageUrl;
  final String? rarity;

  /// 与鱼获 `scientificName` 对齐，用于信息流 / 外键。
  final String speciesScientificName;

  /// `nearshore` | `deep` | `rare`（图鉴筛选用）。
  final String category;

  String get displaySpeciesZh =>
      SpeciesCatalog.tryByScientificName(speciesScientificName)?.speciesZh ?? speciesScientificName;
}
