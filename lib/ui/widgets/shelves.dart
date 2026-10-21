import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/player.dart';
import '../pages/collection_page.dart';
import '../shell.dart';
import '../theme.dart';
import 'artwork.dart';
import 'common.dart';
import 'media_card.dart';
import 'track_tile.dart';

/// A row of a [Shelf]: songs as pages of four, cards as a carousel.
class ShelfView extends StatelessWidget {
  const ShelfView(this.shelf, {super.key});

  final Shelf shelf;

  @override
  Widget build(BuildContext context) {
    if (shelf.tracks.isNotEmpty) {
      return TrackPages(
        title: shelf.title,
        tracks: shelf.tracks,
        action: TextButton(
          onPressed: () => openPage(
            CollectionPage.local(
              title: shelf.title,
              icon: Icons.queue_music_rounded,
              tracks: FixedValue(shelf.tracks),
            ),
          ),
          child: const Text('View all'),
        ),
      );
    }
    return Carousel(
      title: shelf.title,
      height: MediaCard.height,
      itemCount: shelf.cards.length,
      itemBuilder: (context, i) => MediaCard(shelf.cards[i]),
    );
  }
}

/// Songs as horizontally paged columns of four rows, like YouTube Music's
/// quick picks. Tapping one plays the section from there, then its radio.
class TrackPages extends StatelessWidget {
  const TrackPages({
    super.key,
    required this.title,
    required this.tracks,
    this.action,
  });

  final String title;
  final List<Track> tracks;
  final Widget? action;

  static const _rows = 4;
  static const _rowHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 64).clamp(280.0, 400.0);
    return Carousel(
      title: title,
      action: action,
      height: _rows * _rowHeight,
      spacing: 8,
      itemCount: (tracks.length / _rows).ceil(),
      itemBuilder: (context, page) => SizedBox(
        width: width,
        child: Column(
          children: [
            for (
              var i = page * _rows;
              i < (page + 1) * _rows && i < tracks.length;
              i++
            )
              SizedBox(
                height: _rowHeight,
                child: TrackTile(
                  track: tracks[i],
                  padding: EdgeInsets.zero,
                  onTap: () => player.playList(tracks, i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A list that never changes, for pages that take a [ValueListenable].
class FixedValue<T> implements ValueListenable<T> {
  const FixedValue(this.value);

  @override
  final T value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Compact tiles in a grid for jumping back into recent songs.
class QuickGrid extends StatelessWidget {
  const QuickGrid(this.tracks, {super.key});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 640
            ? 3
            : 2;
        const spacing = 10.0;
        final tileWidth =
            (constraints.maxWidth - 2 * pad - (columns - 1) * spacing) /
            columns;
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final (i, t) in tracks.take(columns * 2).indexed)
                SizedBox(
                  width: tileWidth,
                  child: _QuickTile(t, () => player.playList(tracks, i)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile(this.track, this.onTap);

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EncoreColors.surfaceRaised,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Artwork(track.artUrl, size: 56, radius: 0),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
