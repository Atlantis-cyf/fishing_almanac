import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

/// 底部导航：首页 / 中央记录 / 图鉴（与设计稿一致）。
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.active});

  /// `home` | `encyclopedia` | `record`（记录为中央按钮高亮态时可传 record）
  final String active;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 20,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      color: Colors.transparent,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(48)),
      clipBehavior: Clip.none,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.slate900.withValues(alpha: 0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(48)),
          border: Border(top: BorderSide(color: AppColors.cyanNav.withValues(alpha: 0.1))),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryContainer.withValues(alpha: 0.15),
              blurRadius: 40,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 16, 40, 32),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SideItem(
                      icon: Icons.home_rounded,
                      label: '首页',
                      selected: active == 'home',
                      onTap: () => context.go('/home'),
                    ),
                    const SizedBox(width: 72),
                    _SideItem(
                      icon: Icons.menu_book_rounded,
                      label: '图鉴',
                      selected: active == 'encyclopedia',
                      onTap: () => context.go('/encyclopedia'),
                    ),
                  ],
                ),
                Positioned(
                  // Pull the record circle upward so it can overflow above the
                  // bottom bar background (and remain clickable / visible).
                  top: -42,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 18,
                    shadowColor: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(48),
                    clipBehavior: Clip.none,
                    child: InkWell(
                      onTap: () => context.push('/record'),
                      borderRadius: BorderRadius.circular(48),
                      // 整块（圆 +「记录」）可点；圆区 72×72 略大于视觉 64，减少边缘点不到。
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 72,
                              height: 72,
                              child: Center(
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF22d3ee), Color(0xFF0891b2)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primaryContainer.withValues(alpha: 0.55),
                                        blurRadius: 28,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.add, color: Color(0xFF0f172a), size: 30),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '记录',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 1.2,
                                color: AppColors.cyanNav,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.cyanNav : AppColors.slateNavInactive;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
