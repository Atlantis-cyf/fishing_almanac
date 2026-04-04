import 'package:flutter/material.dart';
import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/species_catalog_entry.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

/// 编辑鱼获：物种中文 / 拉丁 / 英文名模糊搜索，下拉对照本地 [SpeciesCatalog]。
class SpeciesCatalogSearchField extends StatelessWidget {
  const SpeciesCatalogSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.optionsMaxHeight = 280,
    this.optionLimit = 16,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double optionsMaxHeight;
  final int optionLimit;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;

    return RawAutocomplete<SpeciesCatalogEntry>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (SpeciesCatalogEntry option) => option.speciesZh,
      optionsBuilder: (TextEditingValue value) {
        return SpeciesCatalog.searchSpeciesForEdit(value.text, limit: optionLimit);
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          onSubmitted: (_) => onFieldSubmitted(),
          style: const TextStyle(color: AppColors.onSurface),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: AppColors.onSurfaceVariant),
            hintText: '搜索或修改鱼种…',
            hintStyle: TextStyle(color: AppColors.onSurfaceVariant.withValues(alpha: 0.55)),
            filled: true,
            fillColor: AppColors.surfaceContainerHighest.withValues(alpha: 0.45),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(color: AppColors.cyanNav.withValues(alpha: 0.45)),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        if (list.isEmpty) return const SizedBox.shrink();

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: const Color(0xFF1a2233),
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: optionsMaxHeight,
                maxWidth: screenW - 48,
                minWidth: screenW - 96,
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: AppColors.outlineVariant.withValues(alpha: 0.25),
                ),
                itemBuilder: (context, index) {
                  final e = list[index];
                  return InkWell(
                    onTap: () => onSelected(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.speciesZh,
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.scientificName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
