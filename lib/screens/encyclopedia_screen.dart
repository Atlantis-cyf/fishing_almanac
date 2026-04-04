import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/data/image_urls.dart';
import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/species_catalog_entry.dart';
import 'package:fishing_almanac/models/species_item.dart';
import 'package:fishing_almanac/analytics/analytics_client.dart';
import 'package:fishing_almanac/repositories/catch_repository.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/widgets/app_network_image.dart';
import 'package:fishing_almanac/widgets/bottom_nav.dart';
import 'package:google_fonts/google_fonts.dart';

class EncyclopediaScreen extends StatefulWidget {
  const EncyclopediaScreen({super.key});

  static String _categoryForCatalog(SpeciesCatalogEntry e) {
    if (e.isRare) return 'rare';
    final d = e.rarityDisplay ?? '';
    if (d.contains('稀有') || d.contains('保护')) return 'rare';
    if (e.taxonomyZh.contains('软骨')) return 'deep';
    return 'nearshore';
  }

  static List<SpeciesItem>? __speciesCache;

  static List<SpeciesItem> get _species {
    return __speciesCache ??= SpeciesCatalog.all
        .where((e) => e.id < 100)
        .map(
          (e) => SpeciesItem(
            id: e.id,
            name: e.nameEn ?? e.scientificName,
            countLabel: '0 渔获',
            imageUrl: e.imageUrl,
            rarity: e.rarityDisplay,
            speciesScientificName: e.scientificName,
            category: _categoryForCatalog(e),
          ),
        )
        .toList();
  }

  @override
  State<EncyclopediaScreen> createState() => _EncyclopediaScreenState();
}

enum _EncyclopediaTab { my, all, rare }

class _EncyclopediaScreenState extends State<EncyclopediaScreen> {
  _EncyclopediaTab _tab = _EncyclopediaTab.my;

  String? _error;

  CatchRepository? _catchRepo;
  void Function()? _catchRepoListener;
  int _catchRepoGen = -1;

  AuthSession? _authSession;
  void Function()? _authSessionListener;

  int _totalCount = 0;

  /// key: `scientific_name`（与 catalog 一致），value: 渔获条数（approved）。
  Map<String, int> _myCatchCounts = const {};

  /// 待解锁占位：三种目标的学名（与 [SpeciesCatalog] 一致）。
  static const List<String> _featuredLockedScientific = <String>[
    'Thunnus thynnus',
    'Anyperodon leucogrammicus',
    'Lutjanus campechanus',
  ];

  @override
  void initState() {
    super.initState();
    _totalCount = _species.length;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final repo = context.read<CatchRepository>();
      _catchRepo = repo;
      _catchRepoGen = repo.dataGeneration;
      _catchRepoListener = () {
        if (!mounted) return;
        if (repo.dataGeneration == _catchRepoGen) return;
        _catchRepoGen = repo.dataGeneration;
        unawaited(_loadEncyclopedia());
      };
      repo.addListener(_catchRepoListener!);

      final auth = context.read<AuthSession>();
      _authSession = auth;
      _authSessionListener = () {
        if (!mounted) return;
        unawaited(_loadEncyclopedia());
      };
      auth.addListener(_authSessionListener!);

      context.read<AnalyticsClient>().trackFireAndForget('encyclopedia_open');
      await _loadEncyclopedia();
    });
  }

  @override
  void dispose() {
    final r = _catchRepo;
    final l = _catchRepoListener;
    if (r != null && l != null) {
      r.removeListener(l);
    }
    final a = _authSession;
    final al = _authSessionListener;
    if (a != null && al != null) {
      a.removeListener(al);
    }
    super.dispose();
  }

  List<SpeciesItem> get _species => EncyclopediaScreen._species;

  Map<String, SpeciesItem> get _speciesByScientific =>
      {for (final s in _species) s.speciesScientificName: s};

  /// 与「全部种类」网格一致：该学名累计渔获 >0 即算解锁。
  bool _isSpeciesUnlocked(String scientificName) => (_myCatchCounts[scientificName] ?? 0) > 0;

  /// 分子：已解锁物种数，始终由 [_myCatchCounts] 推导，避免与卡片解锁态不一致。
  int get _catalogUnlockedSpeciesCount =>
      _myCatchCounts.entries.where((e) => e.value > 0).length;

  Future<void> _loadEncyclopedia() async {
    final api = context.read<ApiClient>();
    final loggedIn = context.read<AuthSession>().isLoggedIn;
    final total = _species.length;
    final counts = <String, int>{};
    String? err;

    if (!loggedIn) {
      try {
        final page = await context.read<CatchRepository>().timelineHome();
        for (final item in page.items) {
          final s = item.scientificName.trim();
          if (s.isEmpty) continue;
          if (s == 'Indeterminate' || s == 'Unnamed species') continue;
          if (!_speciesByScientific.containsKey(s)) continue;
          counts[s] = (counts[s] ?? 0) + 1;
        }
      } catch (e) {
        err = e.toString();
      }
    } else {
      try {
        final myResp = await api.get<dynamic>(EncyclopediaEndpoints.mySpecies);
        final my = myResp.data as Map<String, dynamic>? ?? <String, dynamic>{};
        final species = my['species'];
        if (species is List) {
          for (final row in species) {
            if (row is! Map) continue;
            final map = Map<String, dynamic>.from(row);
            final snDirect = map['scientific_name']?.toString().trim() ?? '';
            final zhLegacy = map['species_zh']?.toString().trim() ?? '';
            final sn = snDirect.isNotEmpty
                ? snDirect
                : (zhLegacy.isNotEmpty
                    ? (SpeciesCatalog.tryBySpeciesZh(zhLegacy)?.scientificName ?? zhLegacy)
                    : '');
            if (sn.isEmpty) continue;
            if (sn == 'Indeterminate' || sn == 'Unnamed species') continue;
            if (!_speciesByScientific.containsKey(sn)) continue;
            final catchCount = map['catch_count'];
            final c = (catchCount as num?)?.toInt() ?? 0;
            if (c <= 0) continue;
            counts[sn] = c;
          }
        }
      } on ApiException catch (e) {
        err = e.message;
      } catch (e) {
        err = e.toString();
      }
    }

    if (!mounted) return;
    setState(() {
      _error = err;
      _totalCount = total;
      _myCatchCounts = counts;
    });
  }

  List<_SpeciesCardModel> _buildAllCards() {
    return _species.map((s) {
      final sci = s.speciesScientificName;
      final catchCount = _myCatchCounts[sci] ?? 0;
      return _SpeciesCardModel(
        speciesItem: s,
        speciesScientificName: sci,
        unlocked: _isSpeciesUnlocked(sci),
        catchCount: catchCount,
      );
    }).toList();
  }

  List<_SpeciesCardModel> _buildMyCards() {
    final unlockedSpecies = _myCatchCounts.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (unlockedSpecies.length >= 3) {
      return unlockedSpecies.map((e) {
        final sci = e.key;
        final item = _speciesByScientific[sci];
        final catchCount = e.value;
        return _SpeciesCardModel(
          speciesItem: item,
          speciesScientificName: sci,
          unlocked: true,
          catchCount: catchCount,
        );
      }).toList();
    }

    final selected = <String>[];
    for (final e in unlockedSpecies) {
      selected.add(e.key);
    }

    for (final sci in _featuredLockedScientific) {
      if (selected.length >= 3) break;
      if (!selected.contains(sci)) selected.add(sci);
    }

    return selected.map((sci) {
      final item = _speciesByScientific[sci];
      final catchCount = _myCatchCounts[sci] ?? 0;
      return _SpeciesCardModel(
        speciesItem: item,
        speciesScientificName: sci,
        unlocked: _isSpeciesUnlocked(sci),
        catchCount: catchCount,
      );
    }).toList();
  }

  List<_SpeciesCardModel> _buildCategoryCards(_EncyclopediaTab tab) {
    final cat = tab == _EncyclopediaTab.rare ? 'rare' : '';
    return _species
        .where((s) => cat.isEmpty || s.category == cat)
        .map((s) {
          final sci = s.speciesScientificName;
          final catchCount = _myCatchCounts[sci] ?? 0;
          return _SpeciesCardModel(
            speciesItem: s,
            speciesScientificName: sci,
            unlocked: _isSpeciesUnlocked(sci),
            catchCount: catchCount,
          );
        })
        .toList();
  }

  List<_SpeciesCardModel> _cardsForTab() {
    switch (_tab) {
      case _EncyclopediaTab.my:
        return _buildMyCards();
      case _EncyclopediaTab.all:
        return _buildAllCards();
      case _EncyclopediaTab.rare:
        return _buildCategoryCards(_tab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cardsForTab();
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
                  style: GoogleFonts.manrope(
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
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.cyanNav.withValues(alpha: 0.35)),
                        ),
                        child: ClipOval(
                          child: AppNetworkImage(url: ImageUrls.avatarEncyclopedia, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '生物索引',
                        style: GoogleFonts.manrope(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        style: const TextStyle(color: AppColors.onSurface),
                        decoration: InputDecoration(
                          hintText: '搜索鱼类、水域或特性...',
                          hintStyle: TextStyle(color: AppColors.outline),
                          prefixIcon: const Icon(Icons.search, color: AppColors.outline),
                          filled: true,
                          fillColor: AppColors.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: AppColors.cyanNav.withValues(alpha: 0.5), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _Chip(
                              label: '我的图鉴',
                              selected: _tab == _EncyclopediaTab.my,
                              onTap: () => setState(() => _tab = _EncyclopediaTab.my),
                            ),
                            const SizedBox(width: 8),
                            _Chip(
                              label: '全部种类',
                              selected: _tab == _EncyclopediaTab.all,
                              onTap: () => setState(() => _tab = _EncyclopediaTab.all),
                            ),
                            const SizedBox(width: 8),
                            _Chip(
                              label: '珍稀种',
                              selected: _tab == _EncyclopediaTab.rare,
                              onTap: () => setState(() => _tab = _EncyclopediaTab.rare),
                            ),
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(color: AppColors.secondaryFixed.withValues(alpha: 0.9), fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '当前进度',
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 1.5,
                                    color: AppColors.outline,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$_catalogUnlockedSpeciesCount / $_totalCount',
                                  style: GoogleFonts.manrope(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.cyanNav,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                              width: 128,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: _totalCount <= 0
                                      ? 0
                                      : (_catalogUnlockedSpeciesCount / _totalCount).clamp(0.0, 1.0),
                                  minHeight: 8,
                                  backgroundColor: AppColors.surfaceContainerHighest,
                                  valueColor: const AlwaysStoppedAnimation(Color(0xFF22d3ee)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final card = cards[index];
                      final s = card.speciesItem;
                      final unlocked = card.unlocked;

                      final bg = unlocked
                          ? AppColors.surfaceContainerHigh
                          : AppColors.surfaceContainerLow.withValues(alpha: 0.35);
                      final titleColor = unlocked ? AppColors.onSurface : AppColors.outlineVariant.withValues(alpha: 0.75);
                      final countColor =
                          unlocked ? AppColors.outline : AppColors.outlineVariant.withValues(alpha: 0.8);

                      return Material(
                        color: bg,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            context.read<AnalyticsClient>().trackFireAndForget(
                                  'encyclopedia_species_click',
                                  properties: <String, dynamic>{
                                    'speciesScientificName': card.speciesScientificName,
                                    'target': 'species-detail',
                                  },
                                );
                            context.push('/species-detail', extra: card.speciesScientificName);
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (s != null)
                                      AppNetworkImage(url: s.imageUrl, fit: BoxFit.cover)
                                    else
                                      Container(color: AppColors.surfaceContainerHighest),
                                    if (!unlocked)
                                      Positioned.fill(
                                        child: Container(color: Colors.white.withValues(alpha: 0.06)),
                                      ),
                                    if (unlocked && s?.rarity != null)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.4),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: AppColors.cyanNav.withValues(alpha: 0.2)),
                                          ),
                                          child: Text(
                                            s!.rarity!,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.cyanNav,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s?.displaySpeciesZh ?? card.speciesScientificName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: titleColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      unlocked ? '${card.catchCount} 渔获' : '尚未捕获',
                                      style: TextStyle(fontSize: 10, color: countColor),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: cards.length,
                  ),
                ),
              ),
            ],
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: AppBottomNav(active: 'encyclopedia')),
        ],
      ),
    );
  }
}

class _SpeciesCardModel {
  const _SpeciesCardModel({
    required this.speciesItem,
    required this.speciesScientificName,
    required this.unlocked,
    required this.catchCount,
  });

  final SpeciesItem? speciesItem;
  final String speciesScientificName;
  final bool unlocked;
  final int catchCount;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Chip(
        label: Text(label),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: selected ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant,
        ),
        backgroundColor: selected ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: const StadiumBorder(),
      ),
    );
  }
}
