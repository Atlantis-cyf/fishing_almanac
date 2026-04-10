import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/analytics/analytics_client.dart';
import 'package:fishing_almanac/analytics/analytics_events.dart';
import 'package:fishing_almanac/data/image_urls.dart';
import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';
import 'package:fishing_almanac/models/feed_detail_extra.dart';
import 'package:fishing_almanac/repositories/catch_repository.dart';
import 'package:fishing_almanac/services/species_catalog_service.dart';
import 'package:fishing_almanac/state/user_profile.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/catch_ui_constants.dart';
import 'package:fishing_almanac/widgets/app_network_image.dart';
import 'package:fishing_almanac/widgets/bottom_nav.dart';
import 'package:fishing_almanac/widgets/catch_image_display.dart';
import 'package:fishing_almanac/theme/app_font.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<List<CatchFeedItem>>? _timelineFuture;
  int _lastGen = -1;
  bool _catalogFetchRequested = false;
  bool _homeViewTracked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_homeViewTracked) {
      _homeViewTracked = true;
      context.read<AnalyticsClient>().trackFireAndForget(AnalyticsEvents.homeView);
    }
    if (!_catalogFetchRequested) {
      _catalogFetchRequested = true;
      unawaited(context.read<SpeciesCatalogService>().fetchIfNeeded());
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<CatchRepository>();
    final profile = context.watch<UserProfile>();
    context.watch<SpeciesCatalogService>();
    if (repo.dataGeneration != _lastGen) {
      _lastGen = repo.dataGeneration;
      _timelineFuture = repo.timelineHome().then((p) => p.items);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final msg = context.read<CatchRepository>().consumePersistenceHint();
        if (msg != null && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
          );
        }
      });
    }
    return FutureBuilder<List<CatchFeedItem>>(
      future: _timelineFuture,
      builder: (context, snap) {
        final timeline = snap.data ?? [];
        final unlockedSpecies = <String>{};
        for (final item in timeline) {
          final s = item.scientificName.trim();
          if (s.isEmpty) continue;
          final k = SpeciesCatalog.normalizeScientificNameKey(s);
          if (k == SpeciesCatalog.normalizeScientificNameKey('Indeterminate') ||
              k == SpeciesCatalog.normalizeScientificNameKey('Unnamed species') ||
              k == SpeciesCatalog.normalizeScientificNameKey(SpeciesCatalog.otherScientificName)) {
            continue;
          }
          unlockedSpecies.add(s);
        }
        final rareSpeciesCount =
            context.read<SpeciesCatalogService>().countUnlockedRareSpecies(unlockedSpecies);
        return Scaffold(
      extendBody: true,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.slate900.withValues(alpha: 0.6),
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.menu, color: AppColors.cyanNav),
                  onPressed: () {},
                ),
                title: Text(
                  '海钓图鉴',
                  style: AppFont.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: AppColors.cyanNav,
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: InkWell(
                      onTap: () => context.push('/profile'),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.cyanNav.withValues(alpha: 0.35), width: 2),
                        ),
                        child: ClipOval(
                          child: AppNetworkImage(url: ImageUrls.avatarHome, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 256,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AppNetworkImage(url: ImageUrls.homeBanner, fit: BoxFit.cover),
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
                            bottom: 24,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      profile.displayName,
                                      style: AppFont.manrope(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.secondaryContainer,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        'LV.8',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.onSecondaryContainer,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '高级钓手 · 活跃于太平洋东域',
                                  style: TextStyle(
                                    color: AppColors.primary.withValues(alpha: 0.95),
                                    fontWeight: FontWeight.w500,
                                  ),
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
                  padding: const EdgeInsets.all(16),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.push('/encyclopedia'),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow.withValues(alpha: 0.5),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _Stat(label: '总捕获数', value: '${timeline.length}', valueColor: Colors.white)),
                            Container(width: 1, height: 48, color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                            Expanded(child: _Stat(label: '解锁品种', value: '${unlockedSpecies.length}', valueColor: AppColors.cyanNav)),
                            Container(width: 1, height: 48, color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                            Expanded(
                              child: _Stat(
                                label: '稀有记录',
                                value: '$rareSpeciesCount',
                                valueColor: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '我的鱼获',
                        style: AppFont.manrope(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                          childAspectRatio: CatchUi.photoAspectWidthOverHeight,
                        ),
                        itemCount: timeline.length,
                        itemBuilder: (context, i) {
                          final item = timeline[i];
                          return Material(
                            color: AppColors.surfaceContainerHighest,
                            child: InkWell(
                              onTap: () => context.push(
                                '/feed-detail',
                                extra: FeedDetailExtra(
                                  initialIndex: i,
                                  anchorCatchId: item.timelineAnchorId,
                                ),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CatchImageDisplay(
                                    memoryBytes: item.imageBytes,
                                    networkUrlFallback: item.imageUrl.isNotEmpty ? item.imageUrl : null,
                                  ),
                                  if (item.fromPublished)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Icon(
                                        Icons.star,
                                        color: Colors.white,
                                        size: 20,
                                        shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                                      ),
                                    ),
                                  if (item.reviewStatus.listLabel.isNotEmpty)
                                    Positioned(
                                      left: 4,
                                      bottom: 4,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.62),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          child: Text(
                                            item.reviewStatus.listLabel,
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: item.reviewStatus == CatchReviewStatus.rejected
                                                  ? AppColors.secondary
                                                  : AppColors.cyanNav,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: AppBottomNav(active: 'home')),
        ],
      ),
    );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.valueColor});

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        const SizedBox(height: 8),
        Text(
          value,
          style: AppFont.manrope(
            fontSize: value.length > 3 ? 18 : 36,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
