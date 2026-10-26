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
      playlistId = null;

  const CollectionPage.local({
    super.key,
    required String this.title,
    required IconData this.icon,
    required ValueListenable<List<Track>> this.tracks,
  }) : browseId = null,
       playlistId = null;

  const CollectionPage.playlist(String this.playlistId, {super.key})
    : browseId = null,
      title = null,
      icon = null,
      tracks = null;

  final String? browseId;
  final String? playlistId;
  final String? title;
  final IconData? icon;
  final ValueListenable<List<Track>>? tracks;

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

class _CollectionView extends StatelessWidget {
  const _CollectionView(
    this.collection, {
    this.icon,
    this.isAlbum = false,
    this.canSave = false,
    this.playlist,
  });

  final Collection collection;
  final IconData? icon;
  final bool isAlbum;

  /// From YouTube Music: can be saved as one of the user's playlists.
  final bool canSave;

  /// The user's own playlist: songs can be reordered and removed.
  final Playlist? playlist;

  @override
  Widget build(BuildContext context) {
    final tracks = collection.tracks;
    final playlist = this.playlist;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Header(
            collection,
            icon:
                icon ??
                (playlist != null && tracks.isEmpty
                    ? Icons.queue_music_rounded
                    : null),
            isAlbum: isAlbum,
            canSave: canSave,
            playlist: playlist,
          ),
        ),
        if (tracks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Message(
              icon: Icons.music_off_rounded,
              text: playlist == null
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
