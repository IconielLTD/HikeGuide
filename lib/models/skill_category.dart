import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The bushcraft skill categories the LLM tags content with, plus an `unknown`
/// fallback for anything unexpected (we never crash on bad data).
enum SkillCategory { navigation, tracking, shelter, fire, foraging, unknown }

SkillCategory skillCategoryFromString(String? raw) {
  switch (raw?.toLowerCase().trim()) {
    case 'navigation':
      return SkillCategory.navigation;
    case 'tracking':
      return SkillCategory.tracking;
    case 'shelter':
      return SkillCategory.shelter;
    case 'fire':
      return SkillCategory.fire;
    case 'foraging':
      return SkillCategory.foraging;
    default:
      return SkillCategory.unknown;
  }
}

extension SkillCategoryX on SkillCategory {
  /// Stable string for storage (DB column / JSON).
  String get id => name;

  String get label {
    switch (this) {
      case SkillCategory.navigation:
        return 'Navigation';
      case SkillCategory.tracking:
        return 'Tracking';
      case SkillCategory.shelter:
        return 'Shelter';
      case SkillCategory.fire:
        return 'Fire';
      case SkillCategory.foraging:
        return 'Foraging';
      case SkillCategory.unknown:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case SkillCategory.navigation:
        return Icons.explore;
      case SkillCategory.tracking:
        return Icons.pets;
      case SkillCategory.shelter:
        return Icons.cabin;
      case SkillCategory.fire:
        return Icons.local_fire_department;
      case SkillCategory.foraging:
        return Icons.grass;
      case SkillCategory.unknown:
        return Icons.terrain;
    }
  }

  /// Accent for the category chip/icon. Fire uses the warning colour.
  Color get color =>
      this == SkillCategory.fire ? AppColors.fire : AppColors.accent;
}
