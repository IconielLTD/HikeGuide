import 'package:flutter/material.dart';

import '../models/skill_category.dart';
import '../services/cache_repository.dart';
import '../theme/app_theme.dart';
import 'guide_list_screen.dart';

/// Guides tab: a LIBRARY of guides you've already generated, grouped into the
/// four skill categories. Titles aren't hardcoded — they accumulate as you
/// generate guides from the Now tab. Tapping a category lists its guides.
class GuidesScreen extends StatefulWidget {
  const GuidesScreen({super.key});

  @override
  State<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends State<GuidesScreen> {
  static const List<SkillCategory> _categories = [
    SkillCategory.navigation,
    SkillCategory.tracking,
    SkillCategory.shelter,
    SkillCategory.fire,
    SkillCategory.foraging,
  ];

  Map<SkillCategory, int> _counts = const {};

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final counts = await CacheRepository.instance.guideCountsByCategory();
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  Future<void> _openCategory(SkillCategory category) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GuideListScreen(category: category)),
    );
    _loadCounts(); // counts may have changed (deletions)
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadCounts,
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Guides you have generated, grouped by skill. Pull to refresh.',
              style: TextStyle(color: AppColors.secondaryText, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ..._categories.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CategoryCard(
                  category: c,
                  count: _counts[c] ?? 0,
                  onTap: () => _openCategory(c),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final SkillCategory category;
  final int count;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(category.icon, size: 30, color: category.color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      count == 0
                          ? 'None yet'
                          : '$count guide${count == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: AppColors.secondaryText, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }
}
