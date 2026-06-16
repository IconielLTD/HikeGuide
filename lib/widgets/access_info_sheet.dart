import 'package:flutter/material.dart';

import '../models/access_guidance.dart';
import '../theme/app_theme.dart';

/// Accent colour for an access category. CRoW / Forestry / Scotland's open
/// access match the Map overlay fills so the banner reads as "you're in the
/// green/teal area"; restriction zones use the warning red, the limited regime a
/// calm amber, and unknown a muted grey.
Color accessCategoryColor(AccessCategory category) {
  switch (category) {
    case AccessCategory.crowOpenAccess:
    case AccessCategory.scotlandOpenAccess:
      return AppColors.openAccess;
    case AccessCategory.forestryEngland:
      return AppColors.forestryEngland;
    case AccessCategory.campingByelawZone:
    case AccessCategory.noMappedRight:
      return AppColors.accent;
    case AccessCategory.militaryNoAccess:
      return AppColors.fire;
    case AccessCategory.unknown:
      return AppColors.secondaryText;
  }
}

IconData accessCategoryIcon(AccessCategory category) {
  switch (category) {
    case AccessCategory.crowOpenAccess:
    case AccessCategory.scotlandOpenAccess:
      return Icons.directions_walk;
    case AccessCategory.forestryEngland:
      return Icons.forest;
    case AccessCategory.campingByelawZone:
      return Icons.cabin;
    case AccessCategory.militaryNoAccess:
      return Icons.dangerous;
    case AccessCategory.noMappedRight:
      return Icons.fork_right;
    case AccessCategory.unknown:
      return Icons.help_outline;
  }
}

/// The relevant country access code to cite in the disclaimer: Scotland's
/// categories point to the Scottish Outdoor Access Code; England/Wales to the
/// Countryside Code.
String _accessCodeFor(AccessCategory category) {
  switch (category) {
    case AccessCategory.scotlandOpenAccess:
    case AccessCategory.militaryNoAccess:
    case AccessCategory.campingByelawZone:
      return 'Scottish Outdoor Access Code';
    case AccessCategory.crowOpenAccess:
    case AccessCategory.forestryEngland:
    case AccessCategory.noMappedRight:
    case AccessCategory.unknown:
      return 'Countryside Code';
  }
}

/// Open the legal/practical guidance for the access [status] (a raw status
/// string, or null for "unknown") as a bottom sheet.
Future<void> showAccessInfo(BuildContext context, String? status) {
  final category = accessCategoryForStatus(status);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _AccessInfoSheet(category: category),
  );
}

class _AccessInfoSheet extends StatelessWidget {
  final AccessCategory category;
  const _AccessInfoSheet({required this.category});

  @override
  Widget build(BuildContext context) {
    final g = guidanceForCategory(category);
    final color = accessCategoryColor(category);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withValues(alpha: 0.7)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(accessCategoryIcon(category), color: color, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      g.title,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                g.summary,
                style: const TextStyle(
                    color: AppColors.primaryText, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 20),
              _Section(
                label: 'You can',
                icon: Icons.check_circle_outline,
                iconColor: AppColors.openAccess,
                items: g.youCan,
              ),
              const SizedBox(height: 18),
              _Section(
                label: 'Take care',
                icon: Icons.warning_amber_rounded,
                iconColor: AppColors.fire,
                items: g.takeCare,
              ),
              if (g.note != null) ...[
                const SizedBox(height: 18),
                _NoteLine(text: g.note!),
              ],
              const SizedBox(height: 20),
              Text(
                'General guidance, not legal advice. Always follow local signs '
                'and the ${_accessCodeFor(category)}.',
                style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12.5,
                    height: 1.4,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final List<String> items;
  const _Section({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t,
                    style: const TextStyle(
                        color: AppColors.primaryText, fontSize: 15, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteLine extends StatelessWidget {
  final String text;
  const _NoteLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: AppColors.secondaryText, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
