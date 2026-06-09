import 'package:flutter/material.dart';

import '../services/live_location.dart';
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
      const MapScreen(),
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
