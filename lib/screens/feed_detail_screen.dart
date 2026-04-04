import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/data/species_catalog.dart';
import 'package:fishing_almanac/models/catch_feed_item.dart';
import 'package:fishing_almanac/models/catch_review_status.dart';
import 'package:fishing_almanac/repositories/catch_repository.dart';
import 'package:fishing_almanac/repositories/catch_timeline_cursor.dart';
import 'package:fishing_almanac/repositories/persistence_exception.dart';
import 'package:fishing_almanac/state/catch_draft.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/catch_ui_constants.dart';
import 'package:fishing_almanac/widgets/bottom_nav.dart';
import 'package:fishing_almanac/widgets/catch_image_display.dart';
import 'package:google_fonts/google_fonts.dart';

/// 信息流加载阶段（初始请求；成功后的「加载更多」用 [_FeedDetailScreenState._loadingMore]）。
enum FeedDetailLoadPhase {
  loading,
  empty,
  error,
  success,
}

class FeedDetailScreen extends StatefulWidget {
  const FeedDetailScreen({
    super.key,
    this.initialIndex = 0,
    this.speciesScientificName,
    this.anchorCatchId,
  });

  final int initialIndex;
  final String? speciesScientificName;
  final String? anchorCatchId;

  @override
  State<FeedDetailScreen> createState() => _FeedDetailScreenState();
}

class _FeedDetailScreenState extends State<FeedDetailScreen> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  FeedDetailLoadPhase _phase = FeedDetailLoadPhase.loading;
  String? _errorMessage;
  final List<CatchFeedItem> _items = [];
  CatchTimelineCursor? _nextCursor;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _didInitialScroll = false;

  int _loadToken = 0;
  String _reloadKey = '';

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onItemPositionsChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FeedDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _didInitialScroll = false;
    }
    if (oldWidget.speciesScientificName != widget.speciesScientificName) {
      _didInitialScroll = false;
    }
    if (oldWidget.anchorCatchId != widget.anchorCatchId) {
      _didInitialScroll = false;
    }
  }

  Future<void> _confirmAndDeletePublished(String publishedId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久删除'),
        content: const Text('是否永久删除此鱼获？删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('否')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('是'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<CatchRepository>().deletePublished(publishedId);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((e) => e.sourcePublishedId == publishedId || e.id == publishedId);
        if (_items.isEmpty) _phase = FeedDetailLoadPhase.empty;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('已删除'), behavior: SnackBarBehavior.floating),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
      );
    } on PersistenceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _onItemPositionsChanged() {
    if (!_hasMore || _loadingMore || _phase != FeedDetailLoadPhase.success) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || _items.isEmpty) return;
    var maxIdx = 0;
    for (final p in positions) {
      maxIdx = math.max(maxIdx, p.index);
    }
    if (maxIdx >= _items.length - 2) {
      unawaited(_loadMore());
    }
  }

  void _scheduleReloadFromKey() {
    final t = _loadToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || t != _loadToken) return;
      final repo = context.read<CatchRepository>();
      final auth = context.read<AuthSession>();
      if (repo.usesRemoteTimeline && !auth.isReady) {
        setState(() {
          _phase = FeedDetailLoadPhase.loading;
          _errorMessage = null;
        });
        return;
      }
      unawaited(_runInitialLoad(t));
    });
  }

  Future<void> _runInitialLoad(int token) async {
    if (!mounted || token != _loadToken) return;
    setState(() {
      _phase = FeedDetailLoadPhase.loading;
      _errorMessage = null;
      _items.clear();
      _nextCursor = null;
      _hasMore = false;
      _loadingMore = false;
      _didInitialScroll = false;
    });

    final repo = context.read<CatchRepository>();
    try {
      final page = (widget.speciesScientificName != null && widget.speciesScientificName!.isNotEmpty)
          ? await repo.timelineForSpecies(widget.speciesScientificName!)
          : await repo.timelineHome();
      if (!mounted || token != _loadToken) return;
      if (page.items.isEmpty) {
        setState(() {
          _phase = FeedDetailLoadPhase.empty;
        });
      } else {
        setState(() {
          _phase = FeedDetailLoadPhase.success;
          _items.addAll(page.items);
          _nextCursor = page.nextCursor;
          _hasMore = page.hasMore;
        });
        _scheduleInitialScroll();
      }
    } on ApiException catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _phase = FeedDetailLoadPhase.error;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _phase = FeedDetailLoadPhase.error;
        _errorMessage = e.toString();
      });
    }
  }

  int _resolveScrollTargetIndex(List<CatchFeedItem> items) {
    if (items.isEmpty) return 0;
    var idx = widget.initialIndex;
    final anchor = widget.anchorCatchId?.trim();
    if (anchor != null && anchor.isNotEmpty) {
      final j = items.indexWhere((e) => e.matchesTimelineAnchor(anchor));
      if (j >= 0) idx = j;
    }
    return idx.clamp(0, items.length - 1);
  }

  void _scheduleInitialScroll() {
    if (_items.isEmpty || _didInitialScroll) return;
    final target = _resolveScrollTargetIndex(_items);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void scrollOnce() {
        try {
          _scrollController.scrollTo(
            index: target,
            alignment: 0,
            duration: Duration.zero,
            curve: Curves.linear,
          );
        } catch (e, st) {
          debugPrint('FeedDetailScreen initial scroll failed: $e\n$st');
        }
      }

      scrollOnce();
      // ScrollablePositionedList 偶发首帧未就绪，多补几帧。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        scrollOnce();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          scrollOnce();
          _didInitialScroll = true;
        });
      });
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _phase != FeedDetailLoadPhase.success) return;
    final cursor = _nextCursor;
    final repo = context.read<CatchRepository>();
    if (!repo.usesRemoteTimeline) return;
    if (cursor == null) return;

    final token = _loadToken;
    setState(() => _loadingMore = true);
    try {
      final page = (widget.speciesScientificName != null && widget.speciesScientificName!.isNotEmpty)
          ? await repo.timelineForSpecies(widget.speciesScientificName!, cursor: cursor)
          : await repo.timelineHome(cursor: cursor);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      debugPrint('FeedDetailScreen _loadMore ApiException: ${e.message}');
      if (!mounted || token != _loadToken) return;
      setState(() => _loadingMore = false);
    } catch (e, st) {
      debugPrint('FeedDetailScreen _loadMore failed: $e\n$st');
      if (!mounted || token != _loadToken) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _onRetry() async {
    _loadToken++;
    final t = _loadToken;
    await _runInitialLoad(t);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<CatchRepository>();
    final auth = context.watch<AuthSession>();
    final key = '${repo.dataGeneration}|${widget.speciesScientificName}|${auth.isReady}|${auth.isLoggedIn}';
    if (key != _reloadKey) {
      _reloadKey = key;
      _loadToken++;
      _scheduleReloadFromKey();
    }

    final title = (widget.speciesScientificName != null && widget.speciesScientificName!.isNotEmpty)
        ? '${SpeciesCatalog.displayZhForScientific(widget.speciesScientificName!)} · 鱼获'
        : '鱼获信息流';

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back, color: Color(0xFFc3f5ff)),
        ),
        title: Text(
          title,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: const Color(0xFFc3f5ff),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.go('/encyclopedia'),
            child: Text('图鉴', style: TextStyle(color: AppColors.cyanNav.withValues(alpha: 0.9))),
          ),
          TextButton(
            onPressed: () => context.go('/home'),
            child: Text('首页', style: TextStyle(color: AppColors.cyanNav.withValues(alpha: 0.9))),
          ),
        ],
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildBody(context),
          const Positioned(left: 0, right: 0, bottom: 0, child: AppBottomNav(active: 'home')),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case FeedDetailLoadPhase.loading:
        return const Center(child: CircularProgressIndicator());
      case FeedDetailLoadPhase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _errorMessage ?? '加载失败',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextButton(onPressed: _onRetry, child: const Text('重试')),
              ],
            ),
          ),
        );
      case FeedDetailLoadPhase.empty:
        return Center(
          child: Text('暂无鱼获', style: TextStyle(color: AppColors.onSurfaceVariant)),
        );
      case FeedDetailLoadPhase.success:
        final extra = (_hasMore && context.read<CatchRepository>().usesRemoteTimeline) ? 1 : 0;
        final count = _items.length + extra;
        final scrollTargetIndex = _resolveScrollTargetIndex(_items).clamp(0, count > 0 ? count - 1 : 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ScrollablePositionedList.builder(
                padding: const EdgeInsets.only(bottom: 100),
                initialScrollIndex: scrollTargetIndex,
                initialAlignment: 0,
                itemCount: count,
                itemScrollController: _scrollController,
                itemPositionsListener: _itemPositionsListener,
                itemBuilder: (context, index) {
                  if (index >= _items.length) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: _loadingMore
                            ? const CircularProgressIndicator()
                            : const SizedBox.shrink(),
                      ),
                    );
                  }
                  final item = _items[index];
                  return _FeedItemCard(
                    item: item,
                    onEditPublished: item.fromPublished &&
                            item.sourcePublishedId != null &&
                            !item.reviewStatus.blocksEditingWhilePending
                        ? () async {
                            final r = context.read<CatchRepository>();
                            final p = await r.getById(item.sourcePublishedId!);
                            if (!context.mounted || p == null) return;
                            context.read<CatchDraft>().loadFromPublished(p);
                            context.push('/edit-catch', extra: item.sourcePublishedId);
                          }
                        : null,
                    onDeletePublished: item.fromPublished && item.sourcePublishedId != null
                        ? () => _confirmAndDeletePublished(item.sourcePublishedId!)
                        : null,
                  );
                },
              ),
            ),
          ],
        );
    }
  }
}

class _FeedItemCard extends StatelessWidget {
  const _FeedItemCard({
    required this.item,
    this.onEditPublished,
    this.onDeletePublished,
  });

  final CatchFeedItem item;
  final VoidCallback? onEditPublished;
  final VoidCallback? onDeletePublished;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.locationLabel,
                        style: TextStyle(fontSize: 12, color: AppColors.onSurface.withValues(alpha: 0.7)),
                      ),
                      if (item.reviewStatus.blocksEditingWhilePending) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.reviewStatus.listLabel,
                          style: TextStyle(fontSize: 11, color: AppColors.cyanNav.withValues(alpha: 0.85)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onDeletePublished != null)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.9),
                    ),
                    tooltip: '更多',
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEditPublished?.call();
                      } else if (value == 'delete') {
                        onDeletePublished?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'edit',
                        enabled: onEditPublished != null,
                        child: const Text('编辑'),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('删除', style: TextStyle(color: Colors.red.shade300)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: CatchUi.photoAspectWidthOverHeight,
            child: CatchImageDisplay(
              memoryBytes: item.imageBytes,
              networkUrlFallback: item.imageUrl.isNotEmpty ? item.imageUrl : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Tag(text: '重量 ${item.weightKg} kg'),
                    const SizedBox(width: 12),
                    _Tag(text: '长度 ${item.lengthCm} cm'),
                  ],
                ),
                if (item.reviewStatus.detailHint.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.reviewStatus.detailHint,
                    style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  item.displaySpeciesZh,
                  style: GoogleFonts.manrope(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.notes,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatTime(item.occurredAt),
                  style: TextStyle(fontSize: 11, color: AppColors.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
