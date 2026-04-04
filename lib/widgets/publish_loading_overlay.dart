import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fishing_almanac/theme/app_colors.dart';

/// 发布/上传时全屏遮罩：主色标题 + 胶囊斜纹缓冲条（参考稿为灰度，此处用 [accentColor]）。
class PublishLoadingOverlay extends StatefulWidget {
  const PublishLoadingOverlay({
    super.key,
    this.accentColor = AppColors.cyanNav,
    this.message = '发布中…',
  });

  final Color accentColor;
  final String message;

  @override
  State<PublishLoadingOverlay> createState() => _PublishLoadingOverlayState();
}

class _PublishLoadingOverlayState extends State<PublishLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final barW = math.min(320.0, w - 80);

    return Material(
      color: Colors.transparent,
      child: AbsorbPointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.88),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.message,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: widget.accentColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: barW,
                    height: 32,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _StripedCapsulePainter(
                            progress: _controller.value,
                            accent: widget.accentColor,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StripedCapsulePainter extends CustomPainter {
  _StripedCapsulePainter({
    required this.progress,
    required this.accent,
  });

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final r = h / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(r),
    );

    canvas.drawRRect(
      rrect,
      Paint()..color = AppColors.surfaceContainerLowest.withValues(alpha: 0.65),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: 0.85),
    );

    canvas.save();
    canvas.clipRRect(rrect);

    const spacing = 9.0;
    const band = 7.0;
    final skew = h * 0.55;
    final travel = spacing * 2 * progress;

    for (double x = -h * 2; x < w + h * 2; x += spacing) {
      final x0 = x + travel;
      final path = Path()
        ..moveTo(x0, 0)
        ..lineTo(x0 + band, 0)
        ..lineTo(x0 + band - skew, h)
        ..lineTo(x0 - skew, h)
        ..close();

      final centerX = x0 + band * 0.5 - skew * 0.5;
      final t = (centerX / w).clamp(0.0, 1.0);
      final opacity = 0.88 * (1.0 - t) + 0.1;

      canvas.drawPath(
        path,
        Paint()..color = accent.withValues(alpha: opacity.clamp(0.12, 0.95)),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StripedCapsulePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.accent != accent;
  }
}
