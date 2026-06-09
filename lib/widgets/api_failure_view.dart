import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Mandatory failure state for every LLM-dependent screen: a short calm line and
/// a retry button. Never a permanent spinner.
class ApiFailureView extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;

  /// Optional technical detail (status code / API error message) shown small and
  /// muted under the calm line — for diagnosing failures.
  final String? detail;

  const ApiFailureView({
    super.key,
    required this.onRetry,
    this.message,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 52, color: AppColors.secondaryText),
            const SizedBox(height: 18),
            Text(
              message ??
                  "No connection — couldn't generate this here. Try again when "
                      'you have signal.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 17,
                height: 1.5,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 12),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.secondaryText.withValues(alpha: 0.8),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
