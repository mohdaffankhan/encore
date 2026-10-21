import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/downloads.dart';
import '../../services/library.dart';
import '../../services/player.dart';
import '../theme.dart';
import 'artwork.dart';
import 'common.dart';
import 'track_menu.dart';

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
        valueListenable: player.nowPlaying,
        builder: (context, _, _) {
          final current = player.current == track;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            // The song's menu: long-press on phones, right-click on desktop.
            onLongPress: () => showTrackMenu(context, track),
            onSecondaryTapUp: (details) =>
                showTrackMenu(context, track, position: details.globalPosition),
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
