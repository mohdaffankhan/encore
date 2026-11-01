import 'package:flutter/material.dart';

import '../../api/innertube.dart' as yt;
import '../../models.dart';
import '../../services/home_cache.dart';
import '../../services/library.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onSearch});

  final VoidCallback onSearch;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Shelf>> _shelves = _load();

  Future<List<Shelf>> _load() async {
    final shelves = await yt.home();
    await saveHome(shelves);
    return shelves;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _shelves = next);
    await next;
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Good night';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: PageTitle(
                  _greeting,
                  // Phones: search and settings up here (desktop has the
                  // sidebar).
                  trailing: wide
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Search',
                              onPressed: widget.onSearch,
                              icon: const Icon(Icons.search_rounded),
                            ),
                            const IconButton(
                              tooltip: 'Settings',
                              onPressed: openSettings,
                              icon: Icon(Icons.settings_outlined),
                            ),
                          ],
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: ValueListenableBuilder(
                  valueListenable: userLibrary.history,
                  builder: (context, history, _) => history.isEmpty
                      ? const SizedBox.shrink()
                      : QuickGrid(history),
                ),
              ),
              FutureBuilder(
                future: _shelves,
                builder: (context, snapshot) {
                  // While the feed loads, or when it can't (offline), the
                  // one from last time.
                  final shelves = snapshot.data ?? lastHome;
                  if (shelves == null) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: snapshot.hasError
                          ? ErrorRetry(
                              message: "Couldn't load your home feed.",
                              onRetry: _refresh,
                            )
                          : const Center(child: CircularProgressIndicator()),
                    );
                  }
                  final failed = snapshot.hasError;
                  return SliverList.builder(
                    itemCount: shelves.length + (failed ? 2 : 1),
                    itemBuilder: (context, i) {
                      if (failed) {
                        if (i == 0) return _Stale(onRetry: _refresh);
                        i--;
                      }
                      return i < shelves.length
                          ? ShelfView(shelves[i])
                          : const SizedBox(height: 40);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Above the last feed when a new one couldn't load.
class _Stale extends StatelessWidget {
  const _Stale({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 18,
            color: EncoreColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Couldn't refresh your home feed",
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: EncoreColors.textSecondary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
