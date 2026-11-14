import 'package:flutter/material.dart';

import '../../api/innertube.dart' as yt;
import '../../models.dart';
import '../../services/art_cache.dart';
import '../../services/player.dart';
import '../theme.dart';
import '../widgets/widgets.dart';

class ArtistPage extends StatefulWidget {
  const ArtistPage(this.browseId, {super.key});

  final String browseId;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  late Future<Artist> _artist = yt.artist(widget.browseId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      extendBodyBehindAppBar: true,
      body: FutureBuilder(
        future: _artist,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: "Couldn't load this artist.",
              onRetry: () =>
                  setState(() => _artist = yt.artist(widget.browseId)),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final artist = snapshot.data!;
          final top = artist.topSongs;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              _Hero(artist),
              if (top.isNotEmpty) ...[
                const SectionHeader('Popular'),
                for (var i = 0; i < top.length; i++)
                  TrackTile(
                    track: top[i],
                    onTap: () => player.playList(top, i),
                  ),
              ],
              for (final shelf in artist.shelves) ShelfView(shelf),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero(this.artist);

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final pad = pagePadding(context);
    final top = artist.topSongs;
    return SizedBox(
      height: (width * 0.42).clamp(300.0, 420.0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (artist.artUrl.isNotEmpty)
            Image(
              image: ResizeImage.resizeIfNeeded(
                (width * MediaQuery.devicePixelRatioOf(context)).ceil(),
                null,
                CachedArt(artist.artUrl),
              ),
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.35),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          DecoratedBox(decoration: BoxDecoration(gradient: heroShade())),
          Positioned(
            left: pad,
            right: pad,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.displaySmall?.copyWith(
                    fontSize: width >= 900 ? 56 : 40,
                  ),
                ),
                if (artist.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    artist.subtitle,
                    style: text.bodyMedium?.copyWith(
                      color: EncoreColors.text.withValues(alpha: 0.75),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    PlayCircleButton(
                      onPressed: top.isEmpty
                          ? null
                          : () => player.playList(top, 0),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: top.isEmpty && artist.radio == null
                          ? null
                          : () => playArtistRadio(artist),
                      icon: const Icon(Icons.radio_rounded, size: 18),
                      label: const Text('Radio'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How an artist's radio is fetched (tests answer themselves).
@visibleForTesting
var fetchArtistRadio = yt.artistRadio;

/// The artist's own radio (YouTube Music's Mix); their top song's radio
/// when the page has none, or it can't load (it played the top song's
/// radio always: not the artist's).
Future<void> playArtistRadio(Artist artist) async {
  if (artist.radio case final radio?) {
    try {
      final tracks = await fetchArtistRadio(radio);
      if (tracks.isNotEmpty) return await player.playList(tracks, 0);
    } catch (e) {
      debugPrint("Artist radio couldn't load: $e");
    }
  }
  if (artist.topSongs.firstOrNull case final top?) await player.playRadio(top);
}

/// The shade over an artist's photo, into the page: from the theme's own
/// colour (a fixed grey stood out as a band in the tinted themes).
@visibleForTesting
LinearGradient heroShade() => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    const Color(0x33000000),
    EncoreColors.surface.withValues(alpha: 0.6),
    EncoreColors.surface,
  ],
  stops: const [0, 0.65, 1],
);

