import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../api/innertube.dart' as yt;
import '../../models.dart';
import '../../services/downloads.dart';
import '../../services/library.dart';
import '../../services/player.dart';
import '../art_colors.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import 'library_page.dart';

/// An album or playlist from YouTube Music, a local list (liked songs,
/// downloads, history), or one of the user's playlists.
class CollectionPage extends StatefulWidget {
  const CollectionPage.remote(String this.browseId, {super.key})
    : title = null,
      icon = null,
      tracks = null,
      playlistId = null,
      searchable = false;

  const CollectionPage.local({
    super.key,
    required String this.title,
    required IconData this.icon,
    required ValueListenable<List<Track>> this.tracks,
    this.searchable = false,
  }) : browseId = null,
       playlistId = null;

  const CollectionPage.playlist(String this.playlistId, {super.key})
    : browseId = null,
      title = null,
      icon = null,
      tracks = null,
      searchable = true;

  final String? browseId;
  final String? playlistId;
  final String? title;
  final IconData? icon;
  final ValueListenable<List<Track>>? tracks;

  /// The user's own list (liked songs, downloads, history, a playlist):
  /// it can be searched and sorted.
  final bool searchable;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  Future<Collection>? _loading;

  @override
  void initState() {
    super.initState();
    if (widget.browseId case final id?) _loading = yt.collection(id);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (widget.playlistId case final id?) {
      body = ValueListenableBuilder(
        valueListenable: userLibrary.playlists,
        builder: (context, _, _) {
          final playlist = userLibrary.playlist(id);
          if (playlist == null) {
            return const Message(
              icon: Icons.queue_music_rounded,
              text: 'This playlist was deleted',
            );
          }
          return _CollectionView(
            Collection(
              title: playlist.name,
              subtitle: [
                songCount(playlist.tracks.length),
                if (playlist.source case final source?) 'Imported from $source',
              ].join(' • '),
              artUrl: '',
              tracks: playlist.tracks,
            ),
            playlist: playlist,
            searchable: true,
          );
        },
      );
    } else if (widget.tracks case final tracks?) {
      body = ValueListenableBuilder(
        valueListenable: tracks,
        builder: (context, list, _) => _CollectionView(
          Collection(
            title: widget.title!,
            subtitle: songCount(list.length),
            artUrl: '',
            tracks: list,
          ),
          icon: widget.icon,
          searchable: widget.searchable,
        ),
      );
    } else {
      body = FutureBuilder(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: "Couldn't load this page.",
              onRetry: () =>
                  setState(() => _loading = yt.collection(widget.browseId!)),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _CollectionView(
            snapshot.data!,
            isAlbum: widget.browseId!.startsWith('MPRE'),
            canSave: true,
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      extendBodyBehindAppBar: true,
      body: body,
    );
  }
}

/// How a list of the user's songs is ordered.
enum SongOrder {
  /// The list's own order: recently added, recently played, or as arranged.
  own,
  title('Title'),
  artist('Artist'),
  album('Album');

  const SongOrder([this.label]);
  final String? label;
}

/// [tracks] matching [query] (in the title, artist or album), in [order].
@visibleForTesting
List<Track> filterSongs(List<Track> tracks, String query, SongOrder order) {
  final words = query.toLowerCase().split(' ').where((w) => w.isNotEmpty);
  final found = [
    for (final t in tracks)
      if (words.every(
        (w) =>
            '${t.title} ${t.artist} ${t.album ?? ''}'.toLowerCase().contains(w),
      ))
        t,
  ];
  String key(Track t) => switch (order) {
    SongOrder.own => '',
    SongOrder.title => t.title,
    SongOrder.artist => '${t.artist}\u0000${t.title}',
    // Songs without an album last.
    SongOrder.album => '${t.album ?? '￿'}\u0000${t.title}',
  }.toLowerCase();
  if (order != SongOrder.own) {
    // Stable: equal keys keep the list's own order.
    final at = {for (final (i, t) in found.indexed) t: i};
    found.sort((a, b) {
      final c = key(a).compareTo(key(b));
      return c != 0 ? c : at[a]!.compareTo(at[b]!);
    });
  }
  return found;
}

class _CollectionView extends StatefulWidget {
  const _CollectionView(
    this.collection, {
    this.icon,
    this.isAlbum = false,
    this.canSave = false,
    this.playlist,
    this.searchable = false,
  });

  final Collection collection;
  final bool searchable;
  final IconData? icon;
  final bool isAlbum;

  /// From YouTube Music: can be saved as one of the user's playlists.
  final bool canSave;

  /// The user's own playlist: songs can be reordered and removed.
  final Playlist? playlist;

  @override
  State<_CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends State<_CollectionView> {
  final _search = TextEditingController();
  var _order = SongOrder.own;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _searchable => widget.searchable;

  /// What [SongOrder.own] is called here.
  String get _ownOrder => widget.playlist != null
      ? 'Custom order'
      : widget.collection.title == 'History'
      ? 'Recently played'
      : 'Recently added';

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final icon = widget.icon;
    final isAlbum = widget.isAlbum;
    final all = collection.tracks;
    final query = _search.text.trim();
    final tracks = _searchable ? filterSongs(all, query, _order) : all;
    // Songs are reordered by hand in the playlist's own order, all shown.
    final playlist = query.isEmpty && _order == SongOrder.own
        ? widget.playlist
        : null;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Header(
            collection,
            icon:
                icon ??
                (widget.playlist != null && all.isEmpty
                    ? Icons.queue_music_rounded
                    : null),
            isAlbum: isAlbum,
            canSave: widget.canSave,
            playlist: widget.playlist,
          ),
        ),
        if (_searchable && all.isNotEmpty)
          SliverToBoxAdapter(
            child: _FilterBar(
              search: _search,
              hint: 'Search songs',
              order: _order,
              ownOrder: _ownOrder,
              onChanged: () => setState(() {}),
              onOrder: (o) => setState(() => _order = o),
            ),
          ),
        if (all.isNotEmpty && tracks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No songs match "$query"',
                textAlign: TextAlign.center,
                style: const TextStyle(color: EncoreColors.textSecondary),
              ),
            ),
          ),
        if (all.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Message(
              icon: Icons.music_off_rounded,
              text: widget.playlist == null
                  ? 'No songs here yet'
                  : 'No songs here yet.\nAdd some from a song\'s ⋯ menu.',
            ),
          ),
        if (playlist != null)
          SliverReorderableList(
            itemCount: tracks.length,
            onReorderItem: (from, to) =>
                userLibrary.moveInPlaylist(playlist.id, from, to),
            itemBuilder: (context, i) => TrackTile(
              key: ValueKey(tracks[i].id),
              track: tracks[i],
              playlistId: playlist.id,
              trailing: ReorderableDragStartListener(
                index: i,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    // No tooltip: on phones it takes the long-press and
                    // the drag never starts.
                    child: Icon(
                      Icons.drag_handle_rounded,
                      semanticLabel: 'Drag to reorder',
                      color: EncoreColors.textTertiary,
                    ),
                  ),
                ),
              ),
              onTap: () => player.playList(tracks, i),
            ),
          )
        else
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) => TrackTile(
              track: tracks[i],
              playlistId: widget.playlist?.id,
              showArt: !isAlbum,
              showAlbum: !isAlbum,
              leading: isAlbum
                  ? SizedBox(
                      width: 32,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: EncoreColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : null,
              onTap: () => player.playList(tracks, i),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

/// Search and sort for a list of the user's songs.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.search,
    required this.hint,
    required this.order,
    required this.ownOrder,
    required this.onChanged,
    required this.onOrder,
  });

  final TextEditingController search;
  final String hint;
  final SongOrder order;
  final String ownOrder;
  final VoidCallback onChanged;
  final ValueChanged<SongOrder> onOrder;

  String _label(SongOrder o) => o.label ?? ownOrder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide(context) ? 24 : 16, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                // The Search page's box, smaller.
                child: SearchBar(
                  controller: search,
                  onChanged: (_) => onChanged(),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  constraints: const BoxConstraints(minHeight: 44),
                  hintText: hint,
                  leading: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: EncoreColors.textSecondary,
                  ),
                  trailing: [
                    if (search.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          search.clear();
                          onChanged();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<SongOrder>(
            tooltip: 'Sort by',
            initialValue: order,
            onSelected: onOrder,
            color: EncoreColors.surfaceRaised,
            itemBuilder: (context) => [
              for (final o in SongOrder.values)
                CheckedPopupMenuItem(
                  value: o,
                  checked: o == order,
                  child: Text(_label(o)),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.sort_rounded,
                    size: 20,
                    color: EncoreColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _label(order),
                    style: const TextStyle(
                      color: EncoreColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
    this.collection, {
    this.icon,
    required this.isAlbum,
    required this.canSave,
    this.playlist,
  });

  final Collection collection;
  final IconData? icon;
  final bool isAlbum;
  final bool canSave;
  final Playlist? playlist;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tracks = collection.tracks;
    final wide = isWide(context);
    final artSize = wide ? 220.0 : 200.0;
    final artUrl = collection.artUrl.isNotEmpty
        ? collection.artUrl
        : tracks.firstOrNull?.artUrl ?? '';
    final art = icon != null
        ? CollectionIcon(icon!, size: artSize)
        : DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 24,
                  offset: Offset(0, 10),
                  color: Color(0x66000000),
                ),
              ],
            ),
            child: Artwork(artUrl, size: artSize, radius: 14),
          );
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final info = Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          playlist != null
              ? 'PLAYLIST'
              : icon != null
              ? 'COLLECTION'
              : isAlbum
              ? 'ALBUM'
              : 'PLAYLIST',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: EncoreColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          collection.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: wide ? text.displaySmall : text.headlineMedium,
        ),
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          children: [
            if (collection.artist case final artist?)
              InkWell(
                onTap: collection.artistId == null
                    ? null
                    : () => openArtist(collection.artistId!),
                child: Text(
                  '$artist  •  ',
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            Text(
              collection.subtitle,
              style: text.bodyMedium?.copyWith(
                color: EncoreColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayCircleButton(
              onPressed: tracks.isEmpty
                  ? null
                  : () => player.playList(tracks, 0),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Shuffle',
              iconSize: 26,
              icon: const Icon(Icons.shuffle_rounded),
              onPressed: tracks.isEmpty
                  ? null
                  : () => player.playList(tracks, 0, shuffled: true),
            ),
            IconButton(
              tooltip: 'Download all',
              iconSize: 26,
              icon: const Icon(Icons.arrow_circle_down_rounded),
              onPressed: tracks.isEmpty
                  ? null
                  : () => downloads.download(tracks),
            ),
            if (canSave)
              IconButton(
                tooltip: 'Save to your playlists',
                iconSize: 26,
                icon: const Icon(Icons.library_add_rounded),
                onPressed: tracks.isEmpty
                    ? null
                    : () {
                        userLibrary.createPlaylist(
                          collection.title,
                          tracks: tracks,
                          source: 'YouTube Music',
                        );
                        showToast(context, 'Saved to your playlists');
                      },
              ),
            if (playlist case final playlist?)
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Playlist options',
                  iconSize: 26,
                  icon: const Icon(Icons.more_horiz_rounded),
                  onPressed: () =>
                      showActionMenu(context, _playlistActions(playlist)),
                ),
              ),
          ],
        ),
      ],
    );
    final pad = pagePadding(context);
    return FutureBuilder(
      future: artColor(artUrl),
      builder: (context, snapshot) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              icon != null
                  ? EncoreColors.accent.withValues(alpha: 0.35)
                  : backdropColor(snapshot.data),
              EncoreColors.surface,
            ],
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          pad,
          MediaQuery.paddingOf(context).top + kToolbarHeight,
          pad,
          20,
        ),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  art,
                  const SizedBox(width: 28),
                  Expanded(child: info),
                ],
              )
            : Column(children: [art, const SizedBox(height: 22), info]),
      ),
    );
  }
}

List<MenuAction> _playlistActions(Playlist playlist) => [
  MenuAction(Icons.edit_rounded, 'Rename', (context) async {
    final name = await askPlaylistName(
      context,
      title: 'Rename playlist',
      initial: playlist.name,
      action: 'Save',
    );
    if (name != null) userLibrary.renamePlaylist(playlist.id, name);
  }),
  if (playlist.tracks.isNotEmpty) ...[
    MenuAction(
      Icons.open_in_new_rounded,
      'Open in YouTube',
      (context) => openInYouTube(context, playlist),
    ),
    MenuAction(
      Icons.copy_rounded,
      'Copy song list',
      (context) => copySongList(context, playlist),
    ),
  ],
  MenuAction(Icons.delete_outline_rounded, 'Delete playlist', (context) async {
    if (!await confirmDeletePlaylist(context, playlist)) return;
    if (context.mounted) await Navigator.of(context).maybePop();
    userLibrary.deletePlaylist(playlist.id);
  }),
];
