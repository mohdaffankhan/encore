import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/player.dart';
import 'pages/artist_page.dart';
import 'pages/collection_page.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/search_page.dart';
import 'player/player_ui.dart';
import 'theme.dart';
import 'widgets/widgets.dart';

final shellKey = GlobalKey<ShellState>();

enum AppTab { home, search, library }

/// Opens [page] inside the current tab (or [tab]), closing the full player
/// if it is open.
void openPage(Widget page, {AppTab? tab}) =>
    shellKey.currentState?._open(page, tab);

void openArtist(String browseId) => openPage(ArtistPage(browseId));

void openCollection(String browseId) =>
    openPage(CollectionPage.remote(browseId));

/// App frame. Desktop: sidebar, content panel and a player bar along the
/// bottom. Phone: bottom navigation with a mini player above it. Each tab
/// has its own navigator, so pages keep the frame visible.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  var _tab = AppTab.home;
  final _navigators = {
    for (final t in AppTab.values) t: GlobalKey<NavigatorState>(),
  };

  static const _destinations = {
    AppTab.home: (Icons.home_outlined, Icons.home_rounded, 'Home'),
    AppTab.search: (Icons.search_rounded, Icons.search_rounded, 'Search'),
    AppTab.library: (
      Icons.library_music_outlined,
      Icons.library_music_rounded,
      'Library',
    ),
  };

  @override
  void initState() {
    super.initState();
    player.error.addListener(_showError);
  }

  @override
  void dispose() {
    player.error.removeListener(_showError);
    super.dispose();
  }

  void _showError() {
    final message = player.error.value;
    if (message == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    player.error.value = null;
  }

  void _open(Widget page, AppTab? tab) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (tab != null && tab != _tab) setState(() => _tab = tab);
    _navigators[tab ?? _tab]!.currentState?.push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _select(AppTab tab) {
    if (tab == _tab) {
      // Selecting the current tab again returns to its first page.
      _navigators[tab]!.currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _tab = tab);
    }
  }

  void _back() {
    final nav = _navigators[_tab]!.currentState!;
    if (nav.canPop()) {
      nav.pop();
    } else if (_tab != AppTab.home) {
      setState(() => _tab = AppTab.home);
    } else {
      SystemNavigator.pop();
    }
  }

  Widget _tabNavigator(AppTab tab, Widget root) => Navigator(
    key: _navigators[tab],
    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => root),
  );

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      index: _tab.index,
      children: [
        _tabNavigator(
          AppTab.home,
          HomePage(onSearch: () => _select(AppTab.search)),
        ),
        _tabNavigator(AppTab.search, const SearchPage()),
        _tabNavigator(AppTab.library, const LibraryPage()),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: isWide(context) ? _desktop(pages) : _phone(pages),
    );
  }

  Widget _desktop(Widget pages) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _Sidebar(
                  selected: _tab,
                  destinations: _destinations,
                  onSelect: _select,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ColoredBox(
                        color: EncoreColors.surface,
                        child: pages,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const NowPlayingBar(),
        ],
      ),
    );
  }

  Widget _phone(Widget pages) {
    return Scaffold(
      body: pages,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          const Divider(),
          NavigationBar(
            selectedIndex: _tab.index,
            onDestinationSelected: (i) => _select(AppTab.values[i]),
            destinations: [
              for (final (icon, selected, label) in _destinations.values)
                NavigationDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selected),
                  label: label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.destinations,
    required this.onSelect,
  });

  final AppTab selected;
  final Map<AppTab, (IconData, IconData, String)> destinations;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 24),
              child: EncoreWordmark(),
            ),
            for (final MapEntry(key: tab, value: (icon, active, label))
                in destinations.entries)
              _SidebarItem(
                icon: tab == selected ? active : icon,
                label: label,
                selected: tab == selected,
                onTap: () => onSelect(tab),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 28, 12, 8),
              child: Text(
                'YOUR MUSIC',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: EncoreColors.textTertiary,
                ),
              ),
            ),
            for (final c in libraryCollections)
              _SidebarItem(
                icon: c.icon,
                label: c.title,
                selected: false,
                onTap: () => openPage(c.page(), tab: AppTab.library),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? EncoreColors.text : EncoreColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? EncoreColors.surfaceHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
