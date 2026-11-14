import 'package:flutter/material.dart';

import '../../services/youtube_sync.dart';
import '../theme.dart';

/// Many things left Encore's library at once (see [YouTubeSync.askAbove]):
/// before they go from the YouTube Music account too, the user says.
/// Pops true to remove them there, false (or dismissed) to keep them.
class RemovalQuestionDialog extends StatelessWidget {
  const RemovalQuestionDialog(this.question, {super.key});

  final RemovalQuestion question;

  static String _count(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : many ?? '${one}s'}';

  /// "228 liked songs, 2 playlists and 30 songs from playlists".
  @visibleForTesting
  static String what(RemovalQuestion q) {
    final parts = [
      if (q.songs > 0) _count(q.songs, 'liked song'),
      if (q.saved > 0)
        _count(
          q.saved,
          'saved album or playlist',
          'saved albums and playlists',
        ),
      if (q.artists > 0) _count(q.artists, 'followed artist'),
      if (q.playlists > 0) _count(q.playlists, 'playlist'),
      if (q.playlistSongs > 0)
        '${_count(q.playlistSongs, 'song')} from playlists',
    ];
    return switch (parts.length) {
      0 => 'nothing',
      1 => parts.single,
      _ => '${parts.take(parts.length - 1).join(', ')} and ${parts.last}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Remove ${what(question)} from YouTube Music?'),
      content: SizedBox(
        width: 460,
        child: Text(
          'They left your library in Encore all at once. If you didn\'t '
          'mean to remove them, keep them: they come back in Encore, and '
          'nothing changes on YouTube Music.',
          style: text.bodyMedium?.copyWith(color: EncoreColors.textSecondary),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove from YouTube Music'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep them'),
        ),
      ],
    );
  }
}
