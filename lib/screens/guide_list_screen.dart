import 'package:flutter/material.dart';

import '../models/guide_summary.dart';
import '../models/skill_category.dart';
import '../services/cache_repository.dart';
import '../theme/app_theme.dart';
import 'guide_screen.dart';

/// Lists the cached guides in one category (newest first). Tap to re-open from
/// cache (no API call); swipe to delete (removes the guide_cache + guide_progress
/// rows). Never touches trip data.
class GuideListScreen extends StatefulWidget {
  final SkillCategory category;
  const GuideListScreen({super.key, required this.category});

  @override
  State<GuideListScreen> createState() => _GuideListScreenState();
}

class _GuideListScreenState extends State<GuideListScreen> {
  List<GuideSummary>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items =
        await CacheRepository.instance.listGuidesByCategory(widget.category);
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _delete(GuideSummary s) async {
    await CacheRepository.instance.deleteGuide(s.title, s.contextHash);
    if (!mounted) return;
    setState(() => _items = _items!
        .where((g) => !(g.title == s.title && g.contextHash == s.contextHash))
        .toList());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Guide deleted.')),
    );
  }

  void _open(GuideSummary s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GuideScreen(
          title: s.title,
          category: s.category,
          cachedContextHash: s.contextHash,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.label)),
      body: items == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : items.isEmpty
              ? _empty()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: AppColors.secondaryText.withValues(alpha: 0.15),
                  ),
                  itemBuilder: (context, i) => _tile(items[i]),
                ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'No ${widget.category.label.toLowerCase()} guides yet. They appear here '
          'after you generate them from a Now-tab opportunity.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.secondaryText, fontSize: 16, height: 1.5),
        ),
      ),
    );
  }

  Widget _tile(GuideSummary s) {
    final subtitle =
        s.contextLabel.isNotEmpty ? s.contextLabel : _formatDate(s.cachedAt);
    return Dismissible(
      key: ValueKey('${s.title}|${s.contextHash}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _delete(s),
      background: Container(
        alignment: Alignment.centerRight,
        color: AppColors.fire.withValues(alpha: 0.85),
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: AppColors.primaryText),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(s.category.icon, color: s.category.color),
        title: Text(s.title,
            style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: AppColors.secondaryText, fontSize: 14)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.secondaryText),
        onTap: () => _open(s),
      ),
    );
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
}
