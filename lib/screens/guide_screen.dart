import 'package:flutter/material.dart';

import '../models/environment_context.dart';
import '../models/guide.dart';
import '../models/skill_category.dart';
import '../services/anthropic_client.dart';
import '../services/cache_repository.dart';
import '../services/content_service.dart';
import '../theme/app_theme.dart';
import '../widgets/api_failure_view.dart';
import '../widgets/needs_setup_view.dart';

enum _GuideState { loading, loaded, needsSetup, failure }

/// Tap-through guide: one step per screen, large serif text, Back/Forward, a
/// progress indicator on top, and no spinner on error (the shared failure state
/// is used instead). Resumes from guide_progress when a cached guide exists.
class GuideScreen extends StatefulWidget {
  /// Generate-on-miss mode supplies [env]; library re-open mode supplies
  /// [cachedContextHash] (read from cache only, never calls the API).
  final EnvironmentContext? env;
  final String title;
  final SkillCategory category;
  final String? cachedContextHash;

  const GuideScreen({
    super.key,
    this.env,
    required this.title,
    required this.category,
    this.cachedContextHash,
  }) : assert(env != null || cachedContextHash != null,
            'Provide env (generate-on-miss) or cachedContextHash (library open).');

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  late final String _hash =
      widget.cachedContextHash ?? CacheRepository.contextHash(widget.env!);

  _GuideState _state = _GuideState.loading;
  Guide? _guide;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _GuideState.loading);
    try {
      final Guide guide;
      if (widget.cachedContextHash != null) {
        // Library re-open: read from cache only, never call the API.
        final cached =
            await CacheRepository.instance.getGuide(widget.title, _hash);
        if (cached == null) {
          if (!mounted) return;
          setState(() => _state = _GuideState.failure);
          return;
        }
        guide = cached;
      } else {
        guide = await ContentService.instance.getGuide(
          widget.env!,
          title: widget.title,
          category: widget.category,
        );
      }
      // Resume only against the now-guaranteed cached guide.
      final saved = await CacheRepository.instance.getGuideProgress(widget.title, _hash);
      if (!mounted) return;
      setState(() {
        _guide = guide;
        _step = (saved ?? 0).clamp(0, guide.steps.length - 1);
        _state = _GuideState.loaded;
      });
    } on NeedsSetupException {
      if (!mounted) return;
      setState(() => _state = _GuideState.needsSetup);
    } on ApiFailureException {
      if (!mounted) return;
      setState(() => _state = _GuideState.failure);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _GuideState.failure);
    }
  }

  void _goTo(int index) {
    final guide = _guide;
    if (guide == null) return;
    final clamped = index.clamp(0, guide.steps.length - 1);
    setState(() => _step = clamped);
    CacheRepository.instance.setGuideProgress(widget.title, _hash, clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: switch (_state) {
        _GuideState.loading => const _GuideLoading(),
        _GuideState.needsSetup => const NeedsSetupView(),
        _GuideState.failure => ApiFailureView(onRetry: _load),
        _GuideState.loaded => _buildLoaded(context),
      },
    );
  }

  Widget _buildLoaded(BuildContext context) {
    final guide = _guide!;
    final total = guide.steps.length;
    final step = guide.steps[_step];
    final isFirst = _step == 0;
    final isLast = _step == total - 1;

    return Column(
      children: [
        LinearProgressIndicator(
          value: total == 0 ? 0 : (_step + 1) / total,
          backgroundColor: AppColors.surface,
          color: AppColors.accent,
          minHeight: 4,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step ${_step + 1} of $total',
                  style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 14,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 16),
                Text(step.text, style: AppText.guideStep),
              ],
            ),
          ),
        ),
        // Standing safety notes — rendered on every step.
        if (guide.isForaging) const _ForagingDisclaimer(),
        if (guide.legalNote != null) _LegalNote(text: guide.legalNote!),
        _NavBar(
          isFirst: isFirst,
          isLast: isLast,
          onBack: isFirst ? null : () => _goTo(_step - 1),
          onForward: isLast ? () => Navigator.of(context).maybePop() : () => _goTo(_step + 1),
        ),
      ],
    );
  }
}

class _GuideLoading extends StatelessWidget {
  const _GuideLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.accent),
          SizedBox(height: 18),
          Text('Writing the guide…',
              style: TextStyle(color: AppColors.secondaryText, fontSize: 16)),
        ],
      ),
    );
  }
}

class _ForagingDisclaimer extends StatelessWidget {
  const _ForagingDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.accent.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: const Row(
        children: [
          Icon(Icons.warning_amber, size: 20, color: AppColors.accent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Verify all identification with a trusted local source before '
              'eating anything.',
              style: TextStyle(color: AppColors.primaryText, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalNote extends StatelessWidget {
  final String text;
  const _LegalNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.fire.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.gavel, size: 20, color: AppColors.fire),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: AppColors.primaryText, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onBack;
  final VoidCallback onForward;

  const _NavBar({
    required this.isFirst,
    required this.isLast,
    required this.onBack,
    required this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryText,
                  side: BorderSide(
                      color: AppColors.secondaryText.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onForward,
                icon: Icon(isLast ? Icons.check : Icons.arrow_forward),
                label: Text(isLast ? 'Finish' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
