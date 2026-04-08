import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/species_catalog_entry.dart';
import 'package:fishing_almanac/services/species_catalog_service.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

/// 编辑鱼获：物种中文 / 拉丁 / 英文名 / 别名 / 学名异名模糊搜索，
/// 先本地匹配，再异步查询后端 `/v1/species/search`。
class SpeciesCatalogSearchField extends StatefulWidget {
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
  State<SpeciesCatalogSearchField> createState() =>
      _SpeciesCatalogSearchFieldState();
}

class _SpeciesCatalogSearchFieldState extends State<SpeciesCatalogSearchField> {
  Timer? _debounce;
  List<SpeciesCatalogEntry> _remoteResults = const [];
  String _lastRemoteQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<SpeciesCatalogEntry>> _buildOptions(
      TextEditingValue value) async {
    final svc = context.read<SpeciesCatalogService>();
    final localHits = SpeciesCatalog.searchSpeciesForEdit(
      value.text,
      limit: widget.optionLimit,
      entries: svc.hasFetched ? svc.all : null,
    );

    // Trigger debounced remote search to supplement local results
    _scheduleRemoteSearch(value.text.trim(), svc);

    // Merge local hits with cached remote results (deduplicate by scientific_name)
    final seen = <String>{};
    final merged = <SpeciesCatalogEntry>[];
    for (final e in localHits) {
      final key =
          SpeciesCatalog.normalizeScientificNameKey(e.scientificName);
      if (seen.add(key)) merged.add(e);
    }
    for (final e in _remoteResults) {
      final key =
          SpeciesCatalog.normalizeScientificNameKey(e.scientificName);
      if (seen.add(key)) merged.add(e);
    }

    return merged.take(widget.optionLimit).toList();
  }

  void _scheduleRemoteSearch(String query, SpeciesCatalogService svc) {
    _debounce?.cancel();
    if (query.isEmpty || query.length < 1) {
      _remoteResults = const [];
      _lastRemoteQuery = '';
      return;
    }
    if (query == _lastRemoteQuery) return;

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await svc.remoteSearch(query);
      if (!mounted) return;
      _lastRemoteQuery = query;
      _remoteResults = results;
      // Rebuild autocomplete options by notifying text controller
      final ctrl = widget.controller;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      ctrl.notifyListeners();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;

    return RawAutocomplete<SpeciesCatalogEntry>(
      textEditingController: widget.controller,
      focusNode: widget.focusNode,
      displayStringForOption: (SpeciesCatalogEntry option) => option.speciesZh,
      optionsBuilder: _buildOptions,
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          onSubmitted: (_) => onFieldSubmitted(),
          style: const TextStyle(color: AppColors.onSurface),
          decoration: InputDecoration(
            prefixIcon:
                const Icon(Icons.search, color: AppColors.onSurfaceVariant),
            hintText: '搜索鱼种名、俗名、学名…',
            hintStyle: TextStyle(
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.55)),
            filled: true,
            fillColor:
                AppColors.surfaceContainerHighest.withValues(alpha: 0.45),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide:
                  BorderSide(color: AppColors.cyanNav.withValues(alpha: 0.45)),
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
                maxHeight: widget.optionsMaxHeight,
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
                  final aliasDisplay = e.allAliasZh;
                  return InkWell(
                    onTap: () => onSelected(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.speciesZh,
                            style: AppFont.manrope(
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
                              color: AppColors.onSurfaceVariant
                                  .withValues(alpha: 0.85),
                            ),
                          ),
                          if (aliasDisplay.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '别名: ${aliasDisplay.join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.onSurfaceVariant
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                          ],
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
