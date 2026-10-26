import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models.dart';
import '../../services/library.dart';
import '../theme.dart';
import 'artwork.dart';
import 'common.dart';

/// Picks a playlist for [tracks] (or makes a new one) and adds them: a
/// sheet on phones, a dialog on desktop.
Future<void> showAddToPlaylist(BuildContext context, List<Track> tracks) async {
  const newPlaylist = '';
  Widget list(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        leading: const _PlaylistArt(null),
        title: const Text('New playlist'),
        onTap: () => Navigator.pop(context, newPlaylist),
      ),
      for (final p in userLibrary.playlists.value)
        ListTile(
          leading: _PlaylistArt(p),
          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            songCount(p.tracks.length),
            style: const TextStyle(color: EncoreColors.textSecondary),
          ),
          onTap: () => Navigator.pop(context, p.id),
        ),
    ],
  );
  const title = Text(
    'Add to playlist',
    style: TextStyle(fontWeight: FontWeight.w700),
  );
  final String? chosen;
  if (isWide(context)) {
    chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: title,
        backgroundColor: EncoreColors.surfaceRaised,
        children: [
          SizedBox(
            width: 360,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: SingleChildScrollView(child: list(context)),
            ),
          ),
        ],
      ),
    );
  } else {
    chosen = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: EncoreColors.surfaceRaised,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Align(alignment: Alignment.centerLeft, child: title),
                ),
                list(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
  if (chosen == null || !context.mounted) return;
  if (chosen == newPlaylist) {
    final name = await askPlaylistName(context);
    if (name == null || !context.mounted) return;
    final playlist = userLibrary.createPlaylist(name, tracks: tracks);
    showToast(context, 'Added to ${playlist.name}');
    return;
  }
  final playlist = userLibrary.playlist(chosen);
  if (playlist == null) return;
  final added = userLibrary.addToPlaylist(chosen, tracks);
  showToast(
    context,
    added == 0
        ? 'Already in ${playlist.name}'
        : tracks.length == 1
        ? 'Added to ${playlist.name}'
        : 'Added ${songCount(added)} to ${playlist.name}',
  );
}

/// Asks for a playlist's name; null when cancelled.
Future<String?> askPlaylistName(
  BuildContext context, {
  String title = 'New playlist',
  String initial = '',
  String action = 'Create',
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      _NameDialog(title: title, initial: initial, action: action),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.action,
  });

  final String title;
  final String initial;
  final String action;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

/// Owns the text field's controller, so it lives until the dialog has
/// finished closing.
class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: EncoreColors.surfaceRaised,
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (_) => _done(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            onPressed: _controller.text.trim().isEmpty ? null : _done,
            child: Text(widget.action),
          ),
        ),
      ],
    );
  }
}

/// Asks before deleting [playlist]; true when confirmed.
Future<bool> confirmDeletePlaylist(
  BuildContext context,
  Playlist playlist,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: EncoreColors.surfaceRaised,
      title: const Text('Delete playlist?'),
      content: Text(
        '"${playlist.name}" will be deleted from Encore. Its songs stay '
        'in your liked songs and downloads.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

String songCount(int n) => n == 1 ? '1 song' : '$n songs';

/// YouTube makes a playlist from a link listing up to this many songs.
const youTubeLinkLimit = 50;

/// Links that open [tracks] as playlists on YouTube, where they can be
/// saved: one per [youTubeLinkLimit] songs.
List<Uri> youTubeLinks(List<Track> tracks) => [
  for (var i = 0; i < tracks.length; i += youTubeLinkLimit)
    Uri.https('www.youtube.com', '/watch_videos', {
      'video_ids': tracks
          .skip(i)
          .take(youTubeLinkLimit)
          .map((t) => t.id)
          .join(','),
    }),
];

/// Opens the playlist on YouTube (asking which part when it needs more
/// than one link).
Future<void> openInYouTube(BuildContext context, Playlist playlist) async {
  final links = youTubeLinks(playlist.tracks);
  if (links.isEmpty) return;
  var link = links.first;
  if (links.length > 1) {
    final part = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: EncoreColors.surfaceRaised,
        title: const Text('Open in YouTube'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'YouTube opens up to $youTubeLinkLimit songs at a time. Save '
              'each part to your YouTube library.',
              style: TextStyle(color: EncoreColors.textSecondary),
            ),
          ),
          for (var i = 0; i < links.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i),
              child: Text(
                'Songs ${i * youTubeLinkLimit + 1}–'
                '${((i + 1) * youTubeLinkLimit).clamp(0, playlist.tracks.length)}',
              ),
            ),
        ],
      ),
    );
    if (part == null) return;
    link = links[part];
  }
  final opened = await launchUrl(link, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) showToast(context, "Couldn't open YouTube");
}

/// "Title - Artist" per line: other apps' importers (TuneMyMusic,
/// Soundiiz) take a pasted list like this.
String songList(Playlist playlist) =>
    [for (final t in playlist.tracks) '${t.title} - ${t.artist}'].join('\n');

Future<void> copySongList(BuildContext context, Playlist playlist) async {
  await Clipboard.setData(ClipboardData(text: songList(playlist)));
  if (context.mounted) {
    showToast(context, 'Copied ${songCount(playlist.tracks.length)}');
  }
}

/// A playlist's picture: its first song's art, or the gradient tile.
class _PlaylistArt extends StatelessWidget {
  const _PlaylistArt(this.playlist);

  final Playlist? playlist;

  @override
  Widget build(BuildContext context) {
    final art = playlist?.tracks.firstOrNull?.artUrl ?? '';
    if (art.isNotEmpty) return Artwork(art, size: 44, radius: 6);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: EncoreColors.brandGradient,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        playlist == null ? Icons.add_rounded : Icons.queue_music_rounded,
        color: Colors.white,
      ),
    );
  }
}
