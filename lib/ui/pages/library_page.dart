import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/account.dart';
import '../../services/downloads.dart';
import '../../services/library.dart';
import '../../services/youtube_sync.dart';
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
            const SyncStatus(),
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
            _RefSection(
              title: 'Albums and playlists',
              refs: userLibrary.savedMedia,
            ),
            _RefSection(title: 'Artists', refs: userLibrary.artists),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Saved albums and playlists, or followed artists: shown once there are
/// any.
class _RefSection extends StatelessWidget {
  const _RefSection({required this.title, required this.refs});

  final String title;
  final ValueListenable<List<MediaRef>> refs;

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder(
      valueListenable: refs,
      builder: (context, list, _) => list.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title),
                for (final r in list)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad - 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => openItem(r),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Artwork(
                              r.artUrl,
                              size: 64,
                              circle: r.kind == MediaKind.artist,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.titleMedium,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    [
                                      switch (r.kind) {
                                        MediaKind.album => 'Album',
                                        MediaKind.playlist => 'Playlist',
                                        MediaKind.artist => 'Artist',
                                      },
                                      if (r.kind != MediaKind.artist &&
                                          r.subtitle.isNotEmpty)
                                        r.subtitle,
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
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Signed in: whether the library is in sync with YouTube Music, and a way
/// to sync now.
class SyncStatus extends StatelessWidget {
  const SyncStatus({super.key, this.inset = true});

  /// Padded as a page row (false: inside a row that is already).
  final bool inset;

  static String describe(
    SyncState state,
    DateTime? last,
    int waiting, {
    int total = 0,
    bool offline = false,
  }) {
    if (waiting > 0 && offline) {
      return 'Waiting for a connection: $waiting to send to YouTube Music';
    }
    if (state == SyncState.failed) {
      return waiting > 0
          ? "Couldn't sync: $waiting ${waiting == 1 ? 'change waits' : 'changes wait'} to be sent"
          : "Couldn't sync with YouTube Music";
    }
    if (waiting > 0) {
      final all = total < waiting ? waiting : total;
      return 'Sending to YouTube Music: ${all - waiting} of $all';
    }
    if (state == SyncState.syncing) return 'Syncing with YouTube Music…';
    if (last == null) return 'Not synced with YouTube Music yet';
    final ago = DateTime.now().difference(last);
    final when = ago.inMinutes < 1
        ? 'just now'
        : ago.inHours < 1
        ? '${ago.inMinutes} min ago'
        : ago.inDays < 1
        ? '${ago.inHours} h ago'
        : '${ago.inDays} d ago';
    return 'Synced with YouTube Music $when';
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([
        account.status,
        youtubeSync.state,
        youtubeSync.lastSynced,
        youtubeSync.pending,
        youtubeSync.total,
        youtubeSync.waiting,
      ]),
      builder: (context, _) {
        if (!account.signedIn) return const SizedBox.shrink();
        final state = youtubeSync.state.value;
        final failed = state == SyncState.failed;
        final left = youtubeSync.pending.value.length;
        final total = max(youtubeSync.total.value, left);
        final offline = youtubeSync.waiting.value;
        final sending = left > 0 && !failed;
        final secondary = text.bodySmall?.copyWith(
          color: EncoreColors.textSecondary,
        );
        return Padding(
          padding: inset
              ? EdgeInsets.fromLTRB(pad, 0, pad - 8, 0)
              : EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    failed || offline
                        ? Icons.sync_problem_rounded
                        : Icons.sync_rounded,
                    size: 18,
                    color: failed
                        ? Theme.of(context).colorScheme.error
                        : EncoreColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      describe(
                        state,
                        youtubeSync.lastSynced.value,
                        left,
                        total: total,
                        offline: offline,
                      ),
                      style: secondary,
                    ),
                  ),
                  TextButton(
                    onPressed: state == SyncState.syncing
                        ? null
                        : offline
                        ? youtubeSync.retryNow
                        : () async {
                            final problem = await youtubeSync.sync();
                            if (problem != null && context.mounted) {
                              showToast(context, problem);
                            }
                          },
                    child: Text(offline ? 'Try now' : 'Sync now'),
                  ),
                ],
              ),
              if (sending) ...[
                Padding(
                  padding: EdgeInsets.only(right: inset ? 8 : 0, top: 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: total == 0 ? null : (total - left) / total,
                      minHeight: 4,
                      semanticsLabel: 'Sending to YouTube Music',
                    ),
                  ),
                ),
                // Long runs: it carries on next time if Encore is closed.
                if (total >= 10)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Encore stays usable meanwhile. If it is closed, '
                      'sending carries on next time.',
                      style: secondary,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
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
