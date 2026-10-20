import 'package:flutter/material.dart';

import '../../api/innertube.dart' as yt;
import '../../models.dart';
import '../../services/library.dart';
import '../widgets/widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onSearch});

  final VoidCallback onSearch;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Shelf>> _shelves = yt.home();

  Future<void> _refresh() async {
    final next = yt.home();
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
                  trailing: wide
                      ? null
                      : IconButton(
                          tooltip: 'Search',
                          onPressed: widget.onSearch,
                          icon: const Icon(Icons.search_rounded),
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
                  if (snapshot.hasError) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: ErrorRetry(
                        message: "Couldn't load your home feed.",
                        onRetry: _refresh,
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final shelves = snapshot.data!;
                  return SliverList.builder(
                    itemCount: shelves.length + 1,
                    itemBuilder: (context, i) => i < shelves.length
                        ? ShelfView(shelves[i])
                        : const SizedBox(height: 40),
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
