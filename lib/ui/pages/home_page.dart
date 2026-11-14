import 'dart:math';

import 'package:flutter/material.dart';

import '../../api/innertube.dart' as yt;
import '../../models.dart';
import '../../services/account.dart';
import '../../services/home_cache.dart';
import '../../services/library.dart';
import '../../services/player.dart';
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

  @override
  void initState() {
    super.initState();
    account.generation.addListener(_accountChanged);
  }

  @override
  void dispose() {
    account.generation.removeListener(_accountChanged);
    super.dispose();
  }

  /// Signed in or out: the feed is made for someone else now.
  void _accountChanged() {
    // Shown by the FutureBuilder: a failure here isn't unhandled.
    final next = _load()..ignore();
    setState(() {
      _shelves = next;
    });
  }

  Future<List<Shelf>> _load() async {
    final at = account.generation.value;
    final shelves = await yt.home();
    // A feed made for whoever was signed in before isn't kept.
    if (at == account.generation.value) await saveHome(shelves);
    return shelves;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _shelves = next;
    });
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
                child: FutureBuilder(
                  future: _shelves,
                  builder: (context, snapshot) => PlaySomething(
                    feed: snapshot.data ?? lastHome ?? const [],
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

/// Starts something to listen to in one tap: a radio (made for the user
/// when signed in) from a song they like, played lately, or that their
/// home feed suggests, picked at random.
class PlaySomething extends StatelessWidget {
  const PlaySomething({super.key, required this.feed, this.random});

  final List<Shelf> feed;
  final Random? random;

  /// Where the radio may start from: the user's own songs first (they're
  /// in twice, so more likely), then the feed's.
  @visibleForTesting
  static List<Track> seeds(List<Shelf> feed) => [
    ...userLibrary.liked.value.take(100),
    ...userLibrary.history.value.take(50),
    ...userLibrary.liked.value.take(100),
    ...userLibrary.history.value.take(50),
    for (final shelf in feed) ...shelf.tracks,
  ];

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return ListenableBuilder(
      listenable: Listenable.merge([userLibrary.liked, userLibrary.history]),
      builder: (context, _) {
        final from = seeds(feed);
        if (from.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () {
                final seed = from[(random ?? Random()).nextInt(from.length)];
                player.playRadio(seed);
              },
              icon: const Icon(Icons.shuffle_rounded),
              label: const Text('Play something'),
            ),
          ),
        );
      },
    );
  }
}
