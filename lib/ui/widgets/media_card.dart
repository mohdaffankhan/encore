import 'package:flutter/material.dart';

import '../../api/innertube.dart' as yt;
import '../../models.dart';
import '../../services/player.dart';
import '../shell.dart';
import '../theme.dart';
import 'artwork.dart';

/// Artwork with a title and subtitle for carousels: an album, playlist,
/// artist (round) or video. On hover it lifts slightly and offers play.
class MediaCard extends StatefulWidget {
  const MediaCard(this.item, {super.key});

  static const width = 168.0;
  static const height = 238.0;

  /// A [MediaRef] or a [Track].
  final Object item;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final (art, title, subtitle, isArtist) = switch (item) {
      MediaRef r => (r.artUrl, r.title, r.subtitle, r.kind == MediaKind.artist),
      Track t => (t.artUrl, t.title, t.artist, false),
      _ => ('', '', '', false),
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => openItem(item),
        child: SizedBox(
          width: MediaCard.width,
          child: Column(
            crossAxisAlignment: isArtist
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: _hovered ? 1.03 : 1,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: Stack(
                  children: [
                    Artwork(
                      art,
                      size: MediaCard.width,
                      radius: 12,
                      circle: isArtist,
                    ),
                    if (!isArtist)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: AnimatedOpacity(
                          opacity: _hovered ? 1 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: _PlayBadge(onTap: () => playItem(item)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: isArtist ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: isArtist ? TextAlign.center : TextAlign.start,
                style: text.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: EncoreColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EncoreColors.text,
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
        ),
      ),
    );
  }
}

/// Opens a card's page; songs and videos play their radio instead.
void openItem(Object item) => switch (item) {
  Track t => player.playRadio(t),
  MediaRef(kind: MediaKind.artist, :final id) => openArtist(id),
  MediaRef(:final id) => openCollection(id),
  _ => null,
};

/// Plays a card's item directly: an album or playlist from the start.
Future<void> playItem(Object item) async {
  switch (item) {
    case MediaRef(kind: MediaKind.album || MediaKind.playlist, :final id):
      final collection = await yt.collection(id);
      if (collection.tracks.isNotEmpty) {
        await player.playList(collection.tracks, 0);
      }
    default:
      openItem(item);
  }
}
