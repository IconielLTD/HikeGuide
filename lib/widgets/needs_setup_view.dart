import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shown when no API key is configured. Points the user to the Info tab instead
/// of firing a doomed request.
class NeedsSetupView extends StatelessWidget {
  final VoidCallback? onOpenInfo;
  final VoidCallback? onRetry;

  const NeedsSetupView({super.key, this.onOpenInfo, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.key_outlined, size: 52, color: AppColors.accent),
            const SizedBox(height: 18),
            const Text(
              'Add your Anthropic API key to generate practice opportunities and '
              'guides.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.primaryText,
                fontSize: 17,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            if (onOpenInfo != null)
              ElevatedButton.icon(
                onPressed: onOpenInfo,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open Info'),
              ),
            if (onRetry != null) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: onRetry,
                child: const Text("I've added my key — check again",
                    style: TextStyle(color: AppColors.accent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
