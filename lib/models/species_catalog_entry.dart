/// 与 `supabase/migrations/0003_species_catalog.sql` 表 `species_catalog` 字段对齐。
class SpeciesCatalogEntry {
  const SpeciesCatalogEntry({
    required this.id,
    required this.speciesZh,
    required this.scientificName,
    required this.taxonomyZh,
    required this.isRare,
    required this.imageUrl,
    required this.maxLengthM,
    required this.maxWeightKg,
    required this.descriptionZh,
    this.nameEn,
    this.encyclopediaCategory,
    this.rarityDisplay,
  });

  final int id;
  final String speciesZh;
  final String scientificName;
  final String taxonomyZh;
  final bool isRare;
  final String imageUrl;
  final double maxLengthM;
  final double maxWeightKg;
  final String descriptionZh;
  final String? nameEn;
  final String? encyclopediaCategory;
  final String? rarityDisplay;
}
