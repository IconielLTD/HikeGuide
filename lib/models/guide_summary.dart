import 'skill_category.dart';

/// Lightweight row for the Guides library list — enough to display and re-open a
/// cached guide without decoding its full JSON.
class GuideSummary {
  final String title;
  final SkillCategory category;
  final String contextHash;
  final String contextLabel; // e.g. "mixed deciduous · summer" (may be empty)
  final DateTime cachedAt;

  const GuideSummary({
    required this.title,
    required this.category,
    required this.contextHash,
    required this.contextLabel,
    required this.cachedAt,
  });
}
