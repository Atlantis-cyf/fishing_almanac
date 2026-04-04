import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/feed_detail_extra.dart';
import 'package:fishing_almanac/repositories/catch_repository.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/catch_ui_constants.dart';
import 'package:fishing_almanac/widgets/app_network_image.dart';
import 'package:fishing_almanac/widgets/bottom_nav.dart';
import 'package:fishing_almanac/widgets/catch_image_display.dart';
import 'package:google_fonts/google_fonts.dart';

class SpeciesDetailScreen extends StatefulWidget {
  const SpeciesDetailScreen({super.key, required this.speciesScientificName});

  final String speciesScientificName;

  @override
  State<SpeciesDetailScreen> createState() => _SpeciesDetailScreenState();
}

class _SpeciesDetailScreenState extends State<SpeciesDetailScreen> {
  Future<List<List<CatchFeedItem>>>? _detailFuture;
  int _lastGen = -1;
  String? _lastScientific;

  @override
  void didUpdateWidget(covariant SpeciesDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speciesScientificName != widget.speciesScientificName) {
      _lastGen = -1;
      _lastScientific = null;
    }
  }

  static int _indexInSpeciesFeed(CatchFeedItem item, List<CatchFeedItem> allForSpecies) {
    final anchor = item.timelineAnchorId;
    return allForSpecies.indexWhere((e) => e.matchesTimelineAnchor(anchor));
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<CatchRepository>();
    if (repo.dataGeneration != _lastGen || widget.speciesScientificName != _lastScientific) {
      _lastGen = repo.dataGeneration;
      _lastScientific = widget.speciesScientificName;
      _detailFuture = Future.wait([
        repo.userPhotosForSpecies(widget.speciesScientificName),
        repo.timelineForSpecies(widget.speciesScientificName).then((p) => p.items),
      ]);
    }

    final entry = SpeciesCatalog.byScientificName(widget.speciesScientificName);
    final titleZh = entry.speciesZh;
    final heroUrl = entry.imageUrl;
    final sci = entry.scientificName;
    final desc = entry.descriptionZh;
    final maxKg = entry.maxWeightKg;
    final maxM = entry.maxLengthM;
    final maxKgStr = maxKg == maxKg.roundToDouble() ? '${maxKg.toInt()}' : maxKg.toStringAsFixed(1);
    final maxMStr = maxM == maxM.roundToDouble() ? maxM.toStringAsFixed(0) : maxM.toStringAsFixed(1);

    return FutureBuilder<List<List<CatchFeedItem>>>(
      future: _detailFuture,
      builder: (context, snap) {
        final userOnly =
            (snap.hasData && snap.data!.length >= 2) ? snap.data![0] : <CatchFeedItem>[];
        final allForSpecies =
            (snap.hasData && snap.data!.length >= 2) ? snap.data![1] : <CatchFeedItem>[];

        return Scaffold(
          extendBody: true,
          backgroundColor: AppColors.background,
          body: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: AppColors.background.withValues(alpha: 0.72),
                    surfaceTintColor: Colors.transparent,
                    leading: IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back, color: Color(0xFFc3f5ff)),
                    ),
                    title: Text(
                      'Species Detail',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: const Color(0xFFecfeff),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 397,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AppNetworkImage(url: heroUrl, fit: BoxFit.cover),
                              Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [Color(0xFF0b1326), Colors.transparent],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 24,
                                right: 24,
                                bottom: 24,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      titleZh,
                                      style: GoogleFonts.manrope(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFFc3f5ff),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      sci.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                        color: AppColors.secondaryFixed,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _GlassStat(
                                            label: '最大重量',
                                            value: maxKgStr,
                                            unit: 'kg',
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: _GlassStat(
                                            label: '最大长度',
                                            value: maxMStr,
                                            unit: 'm',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.id > 0 ? '物种编号 ${entry.id}' : '物种编号 —',
                            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerHigh.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  '分类 · ${entry.taxonomyZh}',
                                  style: TextStyle(fontSize: 12, color: AppColors.onSurface.withValues(alpha: 0.9)),
                                ),
                              ),
                              if (entry.isRare)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondaryFixed.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    entry.rarityDisplay != null ? '稀有种 · ${entry.rarityDisplay}' : '稀有种',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.secondaryFixed,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.secondaryFixed,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '物种描述',
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      child: Text(
                        desc,
                        style: TextStyle(
                          height: 1.6,
                          fontSize: 16,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          Icon(Icons.history, color: AppColors.primaryContainer, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            '我的鱼获',
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryFixed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${userOnly.length} 次捕获',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondaryFixed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (userOnly.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                        child: Text(
                          '暂无已发布照片，去记录一条吧。',
                          style: TextStyle(color: AppColors.onSurfaceVariant, height: 1.5),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                          childAspectRatio: CatchUi.photoAspectWidthOverHeight,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final CatchFeedItem item = userOnly[index];
                            final feedIdx = _indexInSpeciesFeed(item, allForSpecies);
                            final safeIdx = feedIdx >= 0 ? feedIdx : 0;
                            final anchor = item.timelineAnchorId;
                            return Material(
                              color: AppColors.surfaceContainerHighest,
                              child: InkWell(
                                onTap: () => context.push(
                                  '/feed-detail',
                                  extra: FeedDetailExtra(
                                    speciesScientificName: widget.speciesScientificName,
                                    initialIndex: safeIdx,
                                    anchorCatchId: anchor,
                                  ),
                                ),
                                child: CatchImageDisplay(
                                  memoryBytes: item.imageBytes,
                                  networkUrlFallback: item.imageUrl.isNotEmpty ? item.imageUrl : null,
                                ),
                              ),
                            );
                          },
                          childCount: userOnly.length,
                        ),
                      ),
                    ),
                ],
              ),
              const Positioned(left: 0, right: 0, bottom: 0, child: AppBottomNav(active: 'encyclopedia')),
            ],
          ),
        );
      },
    );
  }
}

class _GlassStat extends StatelessWidget {
  const _GlassStat({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF222a3d).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              text: value,
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryContainer,
              ),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
