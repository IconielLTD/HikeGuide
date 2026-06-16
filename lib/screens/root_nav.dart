import 'package:flutter/material.dart';

import '../services/access_land_service.dart' show kScotlandOpenAccessStatus;
import '../services/cache_repository.dart';
import '../services/live_location.dart';
import '../widgets/access_info_sheet.dart';
import 'guides_screen.dart';
import 'info_screen.dart';
import 'journal_screen.dart';
import 'map_screen.dart';
import 'now_screen.dart';

/// Five-tab shell: Now, Map, Guides, Journal, Info. An IndexedStack keeps each
/// tab's state alive when switching (e.g. the map keeps its position).
class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  static const List<String> _titles = ['Now', 'Map', 'Guides', 'Journal', 'Info'];

  // Tabs that actually display live location (Now, Map). Elsewhere we release
  // the GPS stream to save battery.
  static const Set<int> _locationTabs = {0, 1};

  // The one-time Scotland access/safety notice — auto-shown the first time the
  // user's location resolves to Scotland, then remembered so it never nags.
  // This guard stops it firing more than once per app run while the DB read /
  // modal are in flight; persistence across launches lives in CacheRepository.
  bool _scotlandNoticeHandled = false;

  @override
  void initState() {
    super.initState();
    LiveLocation.instance.addListener(_maybeShowScotlandNotice);
  }

  @override
  void dispose() {
    LiveLocation.instance.removeListener(_maybeShowScotlandNotice);
    super.dispose();
  }

  /// Auto-pop the general Scotland notice the first time we're in Scotland
  /// (right to roam, what to avoid, and the live-firing warning). Shown once
  /// ever; afterwards it's only reachable by tapping the Access banner.
  Future<void> _maybeShowScotlandNotice() async {
    if (_scotlandNoticeHandled) return;
    if (LiveLocation.instance.nation != 'Scotland') return;
    _scotlandNoticeHandled = true; // set before any await — fire at most once
    if (await CacheRepository.instance.hasShownNotice('scotland_access')) return;
    await CacheRepository.instance.markNoticeShown('scotland_access');
    if (!mounted) return;
    await showAccessInfo(context, kScotlandOpenAccessStatus);
  }

  void _goToInfo() => _select(4);

  void _select(int i) {
    setState(() => _index = i);
    LiveLocation.instance.setNeeded(_locationTabs.contains(i));
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt each frame, but Flutter retains each tab's State by position +
    // type, so the map keeps its view and the Now tab keeps its loaded cards.
    final screens = <Widget>[
      NowScreen(onOpenInfo: _goToInfo),
      MapScreen(onOpenInfo: _goToInfo),
      const GuidesScreen(),
      const JournalScreen(),
      const InfoScreen(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      // TickerMode pauses animations (e.g. the pulsing GPS marker) in the
      // off-screen tabs, so only the visible tab drives the render loop.
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < screens.length; i++)
            TickerMode(enabled: _index == i, child: screens[i]),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _select,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Now',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            activeIcon: Icon(Icons.menu_book),
            label: 'Guides',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.route_outlined),
            activeIcon: Icon(Icons.route),
            label: 'Journal',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info_outline),
            activeIcon: Icon(Icons.info),
            label: 'Info',
          ),
        ],
      ),
    );
  }
}
