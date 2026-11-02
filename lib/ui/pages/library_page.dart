import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/downloads.dart';
import '../../services/library.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import 'collection_page.dart';
import 'import_page.dart';

/// A list kept on the device, shown in Library and the desktop sidebar.
class LocalCollection {
  const LocalCollection(this.icon, this.title, this.tracks);

  final IconData icon;
  final String title;
  final ValueListenable<List<Track>> tracks;

  Widget page() => CollectionPage.local(
    title: title,
    icon: icon,
    tracks: tracks,
    searchable: true,
  );
}

final libraryCollections = [
  LocalCollection(Icons.favorite_rounded, 'Liked songs', userLibrary.liked),
  LocalCollection(
    Icons.arrow_circle_down_rounded,
    'Downloads',
    userLibrary.downloads,
  ),
  LocalCollection(Icons.history_rounded, 'History', userLibrary.history),
];

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          children: [
            const PageTitle('Library'),
            const SizedBox(height: 8),
            for (final c in libraryCollections)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: pad - 8),
                child: _CollectionRow(c),
              ),
            const SectionHeader('Playlists'),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => newPlaylist(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New playlist'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => openPage(const ImportPage()),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Import playlist'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder(
              valueListenable: userLibrary.playlists,
              builder: (context, playlists, _) => Column(
                children: [
                  if (playlists.isEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
                      child: const Text(
                        'Make your own playlists, or bring them from YouTube '
                        'Music or Spotify with a link.',
                        style: TextStyle(color: EncoreColors.textSecondary),
                      ),
                    ),
                  for (final p in playlists)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: pad - 8),
                      child: _PlaylistRow(p),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow(this.collection);

  final LocalCollection collection;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder(
      valueListenable: collection.tracks,
      builder: (context, list, _) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openPage(collection.page()),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              CollectionIcon(collection.icon, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(collection.title, style: text.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      songCount(list.length),
                      style: text.bodySmall?.copyWith(
                        color: EncoreColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (collection.tracks == userLibrary.downloads)
                ValueListenableBuilder(
                  valueListenable: downloads.progress,
                  builder: (context, pending, _) => pending.isEmpty
                      ? const SizedBox.shrink()
                      : Text(
                          'Downloading ${pending.length}',
                          style: text.bodySmall?.copyWith(
                            color: EncoreColors.accent,
                          ),
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

/// Asks for a name, makes the playlist and opens it.
Future<void> newPlaylist(BuildContext context) async {
  final name = await askPlaylistName(context);
  if (name == null) return;
  final playlist = userLibrary.createPlaylist(name);
  openPage(CollectionPage.playlist(playlist.id), tab: AppTab.library);
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow(this.playlist);

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final art = playlist.tracks.firstOrNull?.artUrl ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openPage(CollectionPage.playlist(playlist.id)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            art.isEmpty
                ? const CollectionIcon(Icons.queue_music_rounded, size: 64)
                : Artwork(art, size: 64, radius: 8),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      songCount(playlist.tracks.length),
                      ?playlist.source,
                    ].join(' • '),
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
    );
  }
}

/// The gradient tile standing in for artwork on local collections.
class CollectionIcon extends StatelessWidget {
  const CollectionIcon(this.icon, {super.key, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: EncoreColors.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.12),
      ),
      child: Icon(icon, size: size * 0.42, color: Colors.white),
    );
  }
}
