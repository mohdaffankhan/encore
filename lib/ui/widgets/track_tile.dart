import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/downloads.dart';
import '../../services/library.dart';
import '../../services/player.dart';
import '../shell.dart';
import '../theme.dart';
import 'artwork.dart';
import 'common.dart';

/// A song row: artwork (or [leading]), title, artist and duration. Highlights
/// itself while it is the current song.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.leading,
    this.showArt = true,
    this.showAlbum = true,
    this.padding,
  });

  final Track track;
  final VoidCallback onTap;
  final Widget? leading;
  final bool showArt;

  /// Shows the album as a column when the row is wide enough.
  final bool showAlbum;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pad =
        padding ?? EdgeInsets.symmetric(horizontal: pagePadding(context) - 8);
    return Padding(
      padding: pad,
      child: ValueListenableBuilder(
        valueListenable: player.index,
        builder: (context, _, _) {
          final current = player.current == track;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    ?leading,
                    if (showArt)
                      Stack(
                        children: [
                          Artwork(track.artUrl, size: 48, radius: 6),
                          if (current)
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.graphic_eq_rounded,
                                color: EncoreColors.accent,
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(
                              fontSize: 15,
                              color: current ? EncoreColors.accent : null,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              _DownloadBadge(track),
                              Expanded(
                                child: Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(
                                    color: EncoreColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (showAlbum &&
                        track.album != null &&
                        constraints.maxWidth >= 720)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text(
                            track.album!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: EncoreColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    if (track.duration case final d?)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          formatDuration(d),
                          style: text.bodySmall?.copyWith(
                            color: EncoreColors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    TrackMenu(track),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DownloadBadge extends StatelessWidget {
  const _DownloadBadge(this.track);

  final Track track;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: userLibrary.downloads,
      builder: (context, _, _) => downloads.isDownloaded(track)
          ? const Padding(
              padding: EdgeInsets.only(right: 5),
              child: Icon(
                Icons.arrow_circle_down_rounded,
                size: 14,
                color: EncoreColors.accent,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// The ⋮ menu for a song: queue, radio, like, download, go to artist/album.
class TrackMenu extends StatelessWidget {
  const TrackMenu(this.track, {super.key, this.color});

  final Track track;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<VoidCallback> item(
      IconData icon,
      String label,
      VoidCallback action,
    ) => PopupMenuItem(
      value: action,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 20, color: EncoreColors.textSecondary),
          const SizedBox(width: 14),
          Text(label),
        ],
      ),
    );
    return PopupMenuButton<VoidCallback>(
      icon: Icon(
        Icons.more_horiz_rounded,
        color: color ?? EncoreColors.textSecondary,
      ),
      tooltip: 'More',
      position: PopupMenuPosition.under,
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        item(
          Icons.playlist_play_rounded,
          'Play next',
          () => player.playNext(track),
        ),
        item(Icons.radio_rounded, 'Start radio', () => player.playRadio(track)),
        if (userLibrary.isLiked(track))
          item(
            Icons.favorite_rounded,
            'Remove from liked',
            () => userLibrary.toggleLike(track),
          )
        else
          item(
            Icons.favorite_border_rounded,
            'Like',
            () => userLibrary.toggleLike(track),
          ),
        if (downloads.isDownloaded(track))
          item(
            Icons.delete_outline_rounded,
            'Remove download',
            () => downloads.remove(track),
          )
        else
          item(
            Icons.download_rounded,
            'Download',
            () => downloads.download([track]),
          ),
        if (track.artistId case final id?)
          item(Icons.person_rounded, 'Go to artist', () => openArtist(id)),
        if (track.albumId case final id?)
          item(Icons.album_rounded, 'Go to album', () => openCollection(id)),
      ],
    );
  }
}
