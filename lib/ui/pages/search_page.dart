import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/innertube.dart' as yt;
import '../../models.dart';
import '../../services/library.dart';
import '../../services/player.dart';
import '../theme.dart';
import '../widgets/widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<String> _suggestions = [];
  String? _query;
  var _filter = yt.SearchFilter.songs;
  Future<List<Object>>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    setState(() {
      _query = null;
      _results = null;
      if (text.trim().isEmpty) _suggestions = [];
    });
    if (text.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final s = await yt.suggestions(text);
        if (mounted && _controller.text == text) {
          setState(() => _suggestions = s);
        }
      } catch (_) {}
    });
  }

  void _submit(String query) {
    query = query.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    _controller.text = query;
    _focus.unfocus();
    userLibrary.addSearch(query);
    setState(() {
      _query = query;
      _results = yt.search(query, _filter);
    });
  }

  void _setFilter(yt.SearchFilter filter) {
    setState(() {
      _filter = filter;
      if (_query case final q?) _results = yt.search(q, filter);
    });
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageTitle('Search'),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SearchBar(
                  controller: _controller,
                  focusNode: _focus,
                  hintText: 'Songs, albums, artists',
                  leading: const Icon(
                    Icons.search_rounded,
                    color: EncoreColors.textSecondary,
                  ),
                  trailing: [
                    ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) => _controller.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _clear,
                            ),
                    ),
                  ],
                  onChanged: _onChanged,
                  onSubmitted: _submit,
                ),
              ),
            ),
            if (_results != null)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  children: [
                    for (final f in yt.SearchFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f.label),
                          selected: f == _filter,
                          onSelected: (_) => _setFilter(f),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_results case final results?) {
      return FutureBuilder(
        future: results,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: 'Search failed.',
              onRetry: () => _submit(_controller.text),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Message(
              icon: Icons.search_off_rounded,
              text: 'Nothing found',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemCount: items.length,
            itemBuilder: (context, i) => switch (items[i]) {
              Track t => TrackTile(track: t, onTap: () => player.playRadio(t)),
              MediaRef r => _RefTile(r),
              _ => const SizedBox.shrink(),
            },
          );
        },
      );
    }
    if (_controller.text.trim().isNotEmpty) {
      return ListView(
        children: [
          for (final s in _suggestions)
            _SimpleRow(
              icon: Icons.search_rounded,
              label: s,
              onTap: () => _submit(s),
              trailing: IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.north_west_rounded, size: 18),
                color: EncoreColors.textTertiary,
                onPressed: () {
                  _controller.text = '$s ';
                  _onChanged(_controller.text);
                },
              ),
            ),
        ],
      );
    }
    return ValueListenableBuilder(
      valueListenable: userLibrary.searches,
      builder: (context, searches, _) {
        if (searches.isEmpty) {
          return const Message(
            icon: Icons.graphic_eq_rounded,
            text: 'Find songs, albums and artists',
          );
        }
        return ListView(
          children: [
            const SectionHeader('Recent searches'),
            for (final q in searches)
              _SimpleRow(
                icon: Icons.history_rounded,
                label: q,
                onTap: () => _submit(q),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: EncoreColors.textTertiary,
                  onPressed: () => userLibrary.removeSearch(q),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad - 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: EncoreColors.textSecondary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _RefTile extends StatelessWidget {
  const _RefTile(this.ref);

  final MediaRef ref;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pad = pagePadding(context);
    final isArtist = ref.kind == MediaKind.artist;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad - 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openItem(ref),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Artwork(ref.artUrl, size: 56, radius: 8, circle: isArtist),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ref.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: EncoreColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: EncoreColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
