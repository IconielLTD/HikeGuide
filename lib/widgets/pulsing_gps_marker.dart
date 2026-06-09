import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Amber GPS dot with a slow outward pulse — the user's current location marker.
class PulsingGpsMarker extends StatefulWidget {
  const PulsingGpsMarker({super.key});

  @override
  State<PulsingGpsMarker> createState() => _PulsingGpsMarkerState();
}

class _PulsingGpsMarkerState extends State<PulsingGpsMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = _controller.value; // 0..1
        return Stack(
          alignment: Alignment.center,
          children: [
            // Expanding, fading pulse ring.
            Opacity(
              opacity: (1.0 - t) * 0.6,
              child: Container(
                width: 14 + t * 30,
                height: 14 + t * 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.35),
                ),
              ),
            ),
            // Solid centre dot with a dark ring for contrast on the map.
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
                border: Border.all(color: AppColors.background, width: 2),
              ),
            ),
          ],
        );
      },
    );
  }
}
