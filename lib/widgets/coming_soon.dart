import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Calm placeholder for tabs not yet built in this phase. Keeps the olive theme
/// consistent and names the phase that fills it in.
class ComingSoon extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const ComingSoon({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.secondaryText),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.secondaryText, fontSize: 16, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
