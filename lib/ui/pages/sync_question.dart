import 'package:flutter/material.dart';

import '../../services/youtube_sync.dart';
import '../theme.dart';

/// Before the first sync after signing in sends anything: what goes to
/// YouTube Music, what comes into Encore, and about how long it takes.
/// Pops true to sync, false to sign out instead.
class SyncQuestion extends StatelessWidget {
  const SyncQuestion(this.plan, {super.key});

  final SyncPlan plan;

  static String _count(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : many ?? '${one}s'}';

  /// "450 liked songs, 3 playlists (1,240 songs), 2 albums and playlists,
  /// 1 artist".
  static String _list(List<String> parts) => switch (parts.length) {
    0 => 'nothing',
    1 => parts.single,
    _ => '${parts.take(parts.length - 1).join(', ')} and ${parts.last}',
  };

  @visibleForTesting
  static String sending(SyncPlan p) => _list([
    if (p.likes > 0) _count(p.likes, 'liked song'),
    if (p.playlists > 0)
      '${_count(p.playlists, 'playlist')} '
          '(${_count(p.playlistSongs, 'song')})'
    else if (p.playlistSongs > 0)
      '${_count(p.playlistSongs, 'song')} in playlists',
    if (p.saved > 0)
      _count(p.saved, 'saved album or playlist', 'saved albums and playlists'),
    if (p.artists > 0) _count(p.artists, 'followed artist'),
  ]);

  @visibleForTesting
  static String bringing(SyncPlan p) => _list([
    if (p.newLikes > 0) _count(p.newLikes, 'liked song'),
    if (p.newPlaylists > 0) _count(p.newPlaylists, 'playlist'),
    if (p.newSaved > 0)
      _count(
        p.newSaved,
        'saved album or playlist',
        'saved albums and playlists',
      ),
    if (p.newArtists > 0) _count(p.newArtists, 'followed artist'),
  ]);

  @visibleForTesting
  static String duration(Duration d) {
    final minutes = (d.inSeconds / 60).ceil();
    return minutes <= 1 ? 'under a minute' : 'about $minutes minutes';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final body = text.bodyMedium;
    final note = text.bodySmall?.copyWith(color: EncoreColors.textSecondary);
    final time = duration(plan.estimate(youtubeSync.spacing));
    return AlertDialog(
      title: const Text('Sync your library with YouTube Music?'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('To YouTube Music: ${sending(plan)}.', style: body),
              const SizedBox(height: 8),
              Text('Into Encore: ${bringing(plan)}.', style: body),
              const SizedBox(height: 16),
              Text(
                'Sending takes $time, a little at a time; Encore stays '
                'usable meanwhile. If Encore is closed, it carries on next '
                'time. Nothing is removed on either side.',
                style: note,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Sign out instead'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sync'),
        ),
      ],
    );
  }
}
